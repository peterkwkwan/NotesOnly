import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Matches [kDesktopShellMinWidth] without importing the shell layer.
const _kWideWebMinWidth = 960.0;

/// One row in [showPelviPickerSheet].
class PelviPickerOption<T> {
  const PelviPickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.searchText,
    this.labelColor,
    this.subtitleColor,
  });

  final T value;
  final String label;
  final String? subtitle;

  /// Lowercased haystack for search (defaults to [label] + [subtitle]).
  final String? searchText;

  /// Optional tint for [label] / [subtitle] (e.g. appointment status words).
  final Color? labelColor;
  final Color? subtitleColor;
}

/// Paper-white picker: bottom sheet on phone / narrow web; centered dialog on
/// wide web. Same search + list selection either way.
Future<T?> showPelviPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<PelviPickerOption<T>> options,
  T? selected,
  bool searchable = false,
  String searchHint = 'Search',
}) {
  final wideWeb = kIsWeb &&
      MediaQuery.sizeOf(context).width >= _kWideWebMinWidth;
  final colors = PelviColors.of(context);

  Widget body({required bool asDialog}) => _PelviPickerSheet<T>(
        title: title,
        options: options,
        selected: selected,
        searchable: searchable,
        searchHint: searchHint,
        asDialog: asDialog,
      );

  if (wideWeb) {
    final maxH = (MediaQuery.sizeOf(context).height * 0.65).clamp(320.0, 560.0);
    return showDialog<T>(
      context: context,
      barrierColor: colors.overlay,
      builder: (context) {
        return Dialog(
          backgroundColor: PelviColors.of(context).surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PelviRadius.lg),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: SizedBox(
            width: 420,
            height: maxH,
            child: body(asDialog: true),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    barrierColor: colors.overlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(PelviRadius.lg)),
    ),
    builder: (context) => body(asDialog: false),
  );
}

class _PelviPickerSheet<T> extends StatefulWidget {
  const _PelviPickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchable,
    required this.searchHint,
    required this.asDialog,
  });

  final String title;
  final List<PelviPickerOption<T>> options;
  final T? selected;
  final bool searchable;
  final String searchHint;
  final bool asDialog;

  @override
  State<_PelviPickerSheet<T>> createState() => _PelviPickerSheetState<T>();
}

class _PelviPickerSheetState<T> extends State<_PelviPickerSheet<T>> {
  String _query = '';

  List<PelviPickerOption<T>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options.where((o) {
      final hay =
          (o.searchText ?? '${o.label} ${o.subtitle ?? ''}').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final filtered = _filtered;

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.asDialog) ...[
          const SizedBox(height: PelviSpace.sm),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: PelviColors.of(context).border,
                borderRadius: BorderRadius.circular(PelviRadius.full),
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PelviSpace.md,
            PelviSpace.md,
            PelviSpace.sm,
            PelviSpace.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title, style: text.titleLarge),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: PelviColors.of(context).inkMuted),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: PelviColors.of(context).chromeBorder),
        if (widget.searchable) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PelviSpace.md,
              PelviSpace.md,
              PelviSpace.md,
              PelviSpace.sm,
            ),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: Icon(
                  Icons.search,
                  color: PelviColors.of(context).inkMuted,
                ),
                filled: true,
                fillColor: PelviColors.of(context).surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PelviRadius.md),
                  borderSide: BorderSide(color: PelviColors.of(context).border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PelviRadius.md),
                  borderSide: BorderSide(color: PelviColors.of(context).border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PelviRadius.md),
                  borderSide: BorderSide(
                    color: PelviColors.of(context).pink700,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _query.trim().isEmpty ? 'Nothing here yet.' : 'No matches.',
                    style: text.bodyMedium?.copyWith(
                      color: PelviColors.of(context).inkMuted,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final o = filtered[i];
                    final isSelected = o.value == widget.selected;
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(o.value),
                      splashColor: PelviColors.of(context).surfaceMuted,
                      highlightColor: PelviColors.of(context).surfaceMuted,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: PelviSpace.md,
                          vertical: PelviSpace.sm + 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? PelviColors.of(context).pink50
                              : PelviColors.of(context).surface,
                          border: isSelected
                              ? Border(
                                  bottom: BorderSide(
                                    color: PelviColors.of(context).pink200,
                                  ),
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    o.label,
                                    style: text.labelLarge?.copyWith(
                                      color: o.labelColor ??
                                          (isSelected
                                              ? PelviColors.of(context).pink700
                                              : PelviColors.of(context).ink),
                                    ),
                                  ),
                                  if (o.subtitle != null &&
                                      o.subtitle!.isNotEmpty)
                                    Text(
                                      o.subtitle!,
                                      style: text.labelMedium?.copyWith(
                                        color: o.subtitleColor,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check,
                                color: PelviColors.of(context).pink700,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    if (widget.asDialog) return column;

    final height = MediaQuery.sizeOf(context).height * 0.92;
    return SizedBox(
      height: height,
      child: SafeArea(
        top: false,
        child: column,
      ),
    );
  }
}
