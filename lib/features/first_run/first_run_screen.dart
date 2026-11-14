import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/org.dart';
import '../shell/desktop_chrome.dart';
import '../../theme/theme.dart';

enum _FirstRunStep { clinic, display }

/// Post-join / first clinic: optional clinic name, then personal display name.
class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({
    super.key,
    required this.onComplete,
  });

  final VoidCallback onComplete;

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _ready = false;
  _FirstRunStep _step = _FirstRunStep.display;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStep());
  }

  Future<void> _loadStep() async {
    final db = AppDatabaseProvider.of(context);
    final roles =
        parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
    final clinic = (await db.getClinicName())?.trim() ?? '';
    final uid = NotesAuth.currentUser?.uid;
    final display = (await db.getPractitionerName(uid: uid))?.trim() ?? '';
    final canNameClinic = roles.isEmpty ||
        roles.contains(OrgRole.owner) ||
        roles.contains(OrgRole.admin);
    final needClinic = canNameClinic && clinic.isEmpty;
    final needDisplay = display.isEmpty;
    if (!mounted) return;
    if (!needClinic && !needDisplay) {
      widget.onComplete();
      return;
    }
    final step = needClinic ? _FirstRunStep.clinic : _FirstRunStep.display;
    final googleName = NotesAuth.currentUser?.displayName?.trim() ?? '';
    setState(() {
      _step = step;
      _controller.clear();
      if (step == _FirstRunStep.display && googleName.isNotEmpty) {
        _controller.text = googleName;
      }
      _ready = true;
      _saving = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final db = AppDatabaseProvider.of(context);
    final trimmed = _controller.text.trim();
    final uid = NotesAuth.currentUser?.uid;
    if (_step == _FirstRunStep.clinic) {
      await db.setClinicName(trimmed);
      if (!mounted) return;
      final display = (await db.getPractitionerName(uid: uid))?.trim() ?? '';
      if (display.isEmpty) {
        final googleName = NotesAuth.currentUser?.displayName?.trim() ?? '';
        setState(() {
          _step = _FirstRunStep.display;
          _controller.clear();
          if (googleName.isNotEmpty) _controller.text = googleName;
          _saving = false;
        });
        return;
      }
      widget.onComplete();
      return;
    }
    await db.setPractitionerName(trimmed, uid: uid);
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Match waiting-clinic / sign-in column on wide viewports (≥960).
    final maxFormWidth =
        isDesktopShell(context) ? 380.0 : double.infinity;
    final askingClinic = _step == _FirstRunStep.clinic;
    final headline = askingClinic
        ? 'What should we call this clinic?'
        : 'What should we call you?';
    final helper = askingClinic
        ? 'Shown in Practice settings. You can change it later.'
        : 'Shown to colleagues in this clinic.';
    final hint = askingClinic ? 'Clinic name' : 'Your name';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxFormWidth),
            child: Padding(
              padding: const EdgeInsets.all(PelviSpace.lg),
              child: !_ready
                  ? Center(
                      child: CircularProgressIndicator(
                        color: PelviColors.of(context).pink700,
                      ),
                    )
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Spacer(),
                          Text(
                            'NotesOnly',
                            textAlign: TextAlign.center,
                            style: text.titleLarge?.copyWith(
                              color: PelviColors.of(context).pink700,
                            ),
                          ),
                          const SizedBox(height: PelviSpace.sm),
                          Text(
                            headline,
                            textAlign: TextAlign.center,
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: PelviSpace.sm),
                          Text(
                            helper,
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              color: PelviColors.of(context).inkMuted,
                            ),
                          ),
                          const SizedBox(height: PelviSpace.xl),
                          TextFormField(
                            controller: _controller,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _continue(),
                            decoration: InputDecoration(hintText: hint),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Enter a name to continue';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: PelviSpace.md),
                          FilledButton(
                            onPressed: _saving ? null : _continue,
                            child: _saving
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color:
                                          PelviColors.of(context).inkInverse,
                                    ),
                                  )
                                : const Text('Continue'),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
