import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'soap_dictation.dart';

/// Editable transcript + S/O/A/P choice → returns text + section, or null if cancelled.
Future<({String text, SoapSection section})?> showDictationApplySheet({
  required BuildContext context,
  required String initialText,
  SoapSection initialSection = SoapSection.subjective,
}) {
  return showModalBottomSheet<({String text, SoapSection section})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PelviColors.surface,
    barrierColor: PelviColors.overlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(PelviRadius.lg)),
    ),
    builder: (context) => _DictationApplySheet(
      initialText: initialText,
      initialSection: initialSection,
    ),
  );
}

class _DictationApplySheet extends StatefulWidget {
  const _DictationApplySheet({
    required this.initialText,
    required this.initialSection,
  });

  final String initialText;
  final SoapSection initialSection;

  @override
  State<_DictationApplySheet> createState() => _DictationApplySheetState();
}

class _DictationApplySheetState extends State<_DictationApplySheet> {
  late final TextEditingController _text;
  late SoapSection _section;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText);
    _section = widget.initialSection;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _append() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop((text: t, section: _section));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    PelviSpace.sm,
                    PelviSpace.page,
                    PelviSpace.md,
                  ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: PelviColors.border,
                    borderRadius: BorderRadius.circular(PelviRadius.full),
                  ),
                ),
              ),
              const SizedBox(height: PelviSpace.md),
              Text('Dictation', style: text.titleLarge),
              const SizedBox(height: PelviSpace.sm),
              Text(
                'Edit, pick a SOAP field, then append.',
                style: text.bodyMedium?.copyWith(color: PelviColors.inkMuted),
              ),
              const SizedBox(height: PelviSpace.md),
              TextField(
                controller: _text,
                minLines: 4,
                maxLines: 8,
                autofocus: true,
                style: text.bodyLarge?.copyWith(color: PelviColors.ink),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: PelviColors.surface,
                ),
              ),
              const SizedBox(height: PelviSpace.md),
              Wrap(
                spacing: PelviSpace.sm,
                runSpacing: PelviSpace.sm,
                children: [
                  for (final s in SoapSection.values)
                    _SectionChip(
                      label: s.label,
                      selected: _section == s,
                      onTap: () => setState(() => _section = s),
                    ),
                ],
              ),
              const SizedBox(height: PelviSpace.lg),
              FilledButton(
                onPressed: _append,
                child: const Text('Append'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PelviColors.pink50 : PelviColors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? PelviColors.pink700 : PelviColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PelviSpace.md,
            vertical: PelviSpace.sm,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? PelviColors.pink700 : PelviColors.ink,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}
