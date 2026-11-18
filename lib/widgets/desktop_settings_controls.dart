import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

/// Cursor-style settings row: label (+ helper) left, control right.
class DesktopSettingsRow extends StatelessWidget {
  const DesktopSettingsRow({
    super.key,
    required this.label,
    required this.control,
    this.helper,
    this.showDivider = true,
  });

  final String label;
  final String? helper;
  final Widget control;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                        height: 1.4,
                      ),
                    ),
                    if (helper != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        helper!,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.45,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              control,
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: c.border),
      ],
    );
  }
}

class DesktopSettingsDropdownItem<T> {
  const DesktopSettingsDropdownItem({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

/// Closed: rounded border + chevron. Open: white menu, soft shadow,
/// hover wash, checkmark on the selected item. Pink/calm accents.
class DesktopSettingsDropdown<T> extends StatefulWidget {
  const DesktopSettingsDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 220,
  });

  final T value;
  final List<DesktopSettingsDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final double width;

  @override
  State<DesktopSettingsDropdown<T>> createState() =>
      _DesktopSettingsDropdownState<T>();
}

class _DesktopSettingsDropdownState<T>
    extends State<DesktopSettingsDropdown<T>> {
  bool _open = false;

  void _setOpen(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
  }

  String get _label {
    for (final item in widget.items) {
      if (item.value == widget.value) return item.label;
    }
    return widget.items.isEmpty ? '' : widget.items.first.label;
  }

  ButtonStyle _itemStyle(PelviPalette c) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed)) {
          return c.surfaceMuted;
        }
        return Colors.transparent;
      }),
      foregroundColor: WidgetStatePropertyAll(c.ink),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      minimumSize: WidgetStatePropertyAll(Size(widget.width, 36)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelviRadius.sm),
        ),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.3),
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      onOpen: () => _setOpen(true),
      onClose: () => _setOpen(false),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(c.ink.withValues(alpha: 0.12)),
        elevation: const WidgetStatePropertyAll(8),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PelviRadius.md),
            side: BorderSide(color: c.border),
          ),
        ),
      ),
      menuChildren: [
        for (final item in widget.items)
          MenuItemButton(
            style: _itemStyle(c),
            onPressed: () => widget.onChanged(item.value),
            child: SizedBox(
              width: widget.width - 24,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: c.ink,
                        fontWeight: item.value == widget.value
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (item.value == widget.value)
                    Icon(Icons.check, size: 16, color: c.pink700),
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, child) {
        return Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(PelviRadius.md),
          child: InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            borderRadius: BorderRadius.circular(PelviRadius.md),
            child: Container(
              width: widget.width,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PelviRadius.md),
                border: Border.all(
                  color: _open ? c.pink700 : c.border,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: c.ink,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more,
                    size: 18,
                    color: _open ? c.pink700 : c.inkMuted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Same chrome as [DesktopSettingsDropdown], with checkmarks on every held
/// value. Tap toggles one item; caller decides persistence.
class DesktopSettingsCheckDropdown<T> extends StatefulWidget {
  const DesktopSettingsCheckDropdown({
    super.key,
    required this.values,
    required this.items,
    required this.onToggle,
    this.isToggleEnabled,
    this.width = 220,
    this.emptyLabel = 'Select',
  });

  final Set<T> values;
  final List<DesktopSettingsDropdownItem<T>> items;
  final ValueChanged<T> onToggle;
  final bool Function(T value)? isToggleEnabled;
  final double width;
  final String emptyLabel;

  @override
  State<DesktopSettingsCheckDropdown<T>> createState() =>
      _DesktopSettingsCheckDropdownState<T>();
}

class _DesktopSettingsCheckDropdownState<T>
    extends State<DesktopSettingsCheckDropdown<T>> {
  bool _open = false;

  void _setOpen(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
  }

  String get _label {
    final labels = [
      for (final item in widget.items)
        if (widget.values.contains(item.value)) item.label,
    ];
    if (labels.isEmpty) return widget.emptyLabel;
    return labels.join(', ');
  }

  ButtonStyle _itemStyle(PelviPalette c) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed)) {
          return c.surfaceMuted;
        }
        return Colors.transparent;
      }),
      foregroundColor: WidgetStatePropertyAll(c.ink),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      minimumSize: WidgetStatePropertyAll(Size(widget.width, 36)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelviRadius.sm),
        ),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.3),
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      onOpen: () => _setOpen(true),
      onClose: () => _setOpen(false),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(c.ink.withValues(alpha: 0.12)),
        elevation: const WidgetStatePropertyAll(8),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PelviRadius.md),
            side: BorderSide(color: c.border),
          ),
        ),
      ),
      menuChildren: [
        for (final item in widget.items)
          MenuItemButton(
            style: _itemStyle(c),
            onPressed: widget.isToggleEnabled?.call(item.value) == false
                ? null
                : () => widget.onToggle(item.value),
            child: SizedBox(
              width: widget.width - 24,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: c.ink,
                        fontWeight: widget.values.contains(item.value)
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (widget.values.contains(item.value))
                    Icon(Icons.check, size: 16, color: c.pink700),
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, child) {
        return Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(PelviRadius.md),
          child: InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            borderRadius: BorderRadius.circular(PelviRadius.md),
            child: Container(
              width: widget.width,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PelviRadius.md),
                border: Border.all(color: _open ? c.pink700 : c.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: c.ink,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more,
                    size: 18,
                    color: _open ? c.pink700 : c.inkMuted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compact right-aligned text field for settings rows.
///
/// With [suffixText], width is intrinsic so the value and suffix sit close —
/// Material's [InputDecoration.suffixText] expands between them.
class DesktopSettingsTextControl extends StatelessWidget {
  const DesktopSettingsTextControl({
    super.key,
    required this.controller,
    this.width = 220,
    this.hint,
    this.suffixText,
    this.keyboardType,
    this.inputFormatters,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final double width;
  final String? hint;
  final String? suffixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final style = TextStyle(fontSize: 13, height: 1.4, color: c.ink);
    if (suffixText != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PelviRadius.md),
          border: Border.all(color: c.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 20),
                  child: TextField(
                    controller: controller,
                    keyboardType: keyboardType,
                    inputFormatters: inputFormatters,
                    style: style,
                    onSubmitted: onSubmitted,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: hint,
                      hintStyle: TextStyle(fontSize: 13, color: c.inkMuted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isCollapsed: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                suffixText!,
                style: TextStyle(fontSize: 13, height: 1.4, color: c.inkMuted),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: style,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13, color: c.inkMuted),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: c.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PelviRadius.md),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PelviRadius.md),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PelviRadius.md),
            borderSide: BorderSide(color: c.pink700),
          ),
        ),
      ),
    );
  }
}
