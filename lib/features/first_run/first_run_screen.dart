import 'package:flutter/material.dart';

import '../../data/database_provider.dart';
import '../../theme/theme.dart';

/// Tiny first-run: capture practitioner / clinic name, then enter the shell.
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final db = AppDatabaseProvider.of(context);
    await db.setPractitionerName(_controller.text);
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PelviSpace.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  'Pelvi',
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(
                    color: PelviColors.pink700,
                  ),
                ),
                const SizedBox(height: PelviSpace.sm),
                Text(
                  'What should we call your practice?',
                  textAlign: TextAlign.center,
                  style: text.titleMedium,
                ),
                const SizedBox(height: PelviSpace.sm),
                Text(
                  'This appears in settings and exports. You can change it later.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: PelviColors.inkMuted),
                ),
                const SizedBox(height: PelviSpace.xl),
                TextFormField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _continue(),
                  decoration: const InputDecoration(
                    hintText: 'Clinic or practitioner name',
                  ),
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
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: PelviColors.inkInverse,
                          ),
                        )
                      : const Text('Continue'),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
