import 'package:flutter/material.dart';
import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../theme/theme.dart';
import 'phone_country_names.dart';

/// What the phone field is showing, and the E.164 string to store.
class PhoneInput {
  const PhoneInput({
    required this.iso,
    required this.national,
    required this.e164,
  });

  final IsoCode iso;
  final String national;
  final String e164;
}

/// Default country is Hong Kong. A leading `+` selects the calling code.
PhoneInput resolvePhoneInput(String raw, {IsoCode iso = IsoCode.HK}) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('+')) {
    try {
      final parsed = PhoneNumber.parse(trimmed);
      final nsn = parsed.nsn.replaceAll(_nonDigit, '');
      return PhoneInput(
        iso: parsed.isoCode,
        national: PhoneNumberFormatter.formatNsn(nsn, parsed.isoCode),
        e164: nsn.isEmpty ? '' : '+${parsed.countryCode}$nsn',
      );
    } on PhoneNumberException {
      return PhoneInput(iso: iso, national: trimmed, e164: '');
    }
  }
  final digits = trimmed.replaceAll(_nonDigit, '');
  if (digits.isEmpty) {
    return PhoneInput(iso: iso, national: '', e164: '');
  }
  final code = PhoneNumber(isoCode: iso, nsn: '').countryCode;
  return PhoneInput(
    iso: iso,
    national: PhoneNumberFormatter.formatNsn(digits, iso),
    e164: '+$code$digits',
  );
}

/// Readable form of a stored number. Legacy strings without `+` stay as stored.
String displayPhone(String stored) {
  final trimmed = stored.trim();
  if (!trimmed.startsWith('+')) return stored;
  final input = resolvePhoneInput(trimmed);
  if (input.national.isEmpty) return stored;
  final code = PhoneNumber(isoCode: input.iso, nsn: '').countryCode;
  return '+$code ${input.national}';
}

String phoneFlag(IsoCode iso) {
  final name = iso.name;
  if (name.length != 2) return name;
  return String.fromCharCodes([
    name.codeUnitAt(0) + 127397,
    name.codeUnitAt(1) + 127397,
  ]);
}

class PhoneCountry {
  const PhoneCountry(this.iso, this.code);
  final IsoCode iso;
  final String code;

  String get name => phoneCountryName(iso);
}

final List<PhoneCountry> phoneCountries = () {
  final list =
      <PhoneCountry>[
        for (final entry in countryCodeToIsoCode.entries)
          for (final iso in entry.value) PhoneCountry(iso, entry.key),
      ]..sort((a, b) {
        if (a.iso == IsoCode.HK) return -1;
        if (b.iso == IsoCode.HK) return 1;
        return a.iso.name.compareTo(b.iso.name);
      });
  return list;
}();

/// Case-insensitive match on ISO code, dial code, or English country name.
bool matchesPhoneCountry(PhoneCountry country, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final iso = country.iso.name.toLowerCase();
  final name = country.name.toLowerCase();
  final dial = country.code;
  if (iso.contains(q) || name.contains(q) || '+$dial'.contains(q)) {
    return true;
  }
  final dialQuery = q.startsWith('+') ? q.substring(1) : q;
  return dialQuery.isNotEmpty && dial.contains(dialQuery);
}

List<PhoneCountry> filterPhoneCountries(String query) {
  final q = query.trim();
  if (q.isEmpty) return phoneCountries;
  return [
    for (final country in phoneCountries)
      if (matchesPhoneCountry(country, q)) country,
  ];
}

/// One phone field: flag and calling code on the field, national number beside them.
///
/// [controller] holds the E.164 string (or empty). The visible text is the
/// national format for the selected country.
class PhoneField extends StatefulWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.compact = false,
    this.textInputAction,
  });

  final TextEditingController controller;
  final bool compact;
  final TextInputAction? textInputAction;

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  late final TextEditingController _national;
  late final TextEditingController _countrySearch;
  late final FocusNode _focus;
  late IsoCode _iso;
  var _applying = false;

  @override
  void initState() {
    super.initState();
    final input = resolvePhoneInput(widget.controller.text);
    _iso = input.iso;
    _national = TextEditingController(text: input.national);
    _countrySearch = TextEditingController();
    _focus = FocusNode()..addListener(_onFocus);
    if (widget.controller.text != input.e164) {
      widget.controller.text = input.e164;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _national.dispose();
    _countrySearch.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  void _onChanged(String raw) {
    if (_applying) return;
    _apply(resolvePhoneInput(raw, iso: _iso), raw);
  }

  void _select(IsoCode iso) {
    _apply(resolvePhoneInput(_national.text, iso: iso), _national.text);
  }

  void _apply(PhoneInput input, String raw) {
    _applying = true;
    final isoChanged = _iso != input.iso;
    _iso = input.iso;
    final atEnd = raw.trimLeft().startsWith('+');
    final cursor = atEnd
        ? input.national.length
        : _offsetAfterDigits(
            input.national,
            _digitsBefore(raw, _national.selection.baseOffset),
          );
    final next = TextEditingValue(
      text: input.national,
      selection: TextSelection.collapsed(
        offset: cursor.clamp(0, input.national.length),
      ),
    );
    if (_national.value != next) _national.value = next;
    if (widget.controller.text != input.e164) {
      widget.controller.text = input.e164;
    }
    _applying = false;
    if (isoChanged && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final field = TextField(
      controller: _national,
      focusNode: _focus,
      keyboardType: TextInputType.phone,
      textInputAction: widget.textInputAction,
      style: TextStyle(fontSize: 13, height: 1.2, color: c.ink),
      cursorColor: c.pink700,
      onChanged: _onChanged,
      decoration: widget.compact
          ? InputDecoration(
              isCollapsed: true,
              filled: false,
              // Outer DecoratedBox owns the border; kill theme OutlineInputBorders.
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'Phone',
              hintStyle: TextStyle(
                fontSize: 13,
                height: 1.2,
                color: c.inkMuted,
              ),
            )
          : InputDecoration(hintText: 'Optional', prefix: _affix(c)),
    );
    if (!widget.compact) return field;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        border: Border.all(color: _focus.hasFocus ? c.pink700 : c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _affix(c),
            const SizedBox(width: 6),
            Expanded(child: field),
          ],
        ),
      ),
    );
  }

  Widget _affix(PelviPalette c) {
    final code = PhoneNumber(isoCode: _iso, nsn: '').countryCode;
    final filtered = filterPhoneCountries(_countrySearch.text);
    return MenuAnchor(
      style: const MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(280, 360)),
      ),
      onOpen: () {
        _countrySearch.clear();
        setState(() {});
      },
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _countrySearch,
            autofocus: true,
            style: TextStyle(fontSize: 13, color: c.ink),
            cursorColor: c.pink700,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search country',
              hintStyle: TextStyle(fontSize: 13, color: c.inkMuted),
              prefixIcon: Icon(Icons.search, size: 18, color: c.inkMuted),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                borderSide: BorderSide(color: c.pink700, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (filtered.isEmpty)
          MenuItemButton(
            onPressed: null,
            child: Text(
              'No matches',
              style: TextStyle(fontSize: 13, color: c.inkMuted),
            ),
          )
        else
          for (final country in filtered)
            MenuItemButton(
              onPressed: () => _select(country.iso),
              child: Text(
                '${phoneFlag(country.iso)}  +${country.code}  ${country.name}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
      ],
      builder: (context, menu, _) {
        return Tooltip(
          message: 'Country',
          child: InkWell(
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  phoneFlag(_iso),
                  style: const TextStyle(fontSize: 14, height: 1),
                ),
                const SizedBox(width: 4),
                Text(
                  '+$code',
                  style: TextStyle(fontSize: 13, height: 1, color: c.ink),
                ),
                Icon(Icons.arrow_drop_down, size: 16, color: c.inkMuted),
              ],
            ),
          ),
        );
      },
    );
  }
}

final _nonDigit = RegExp(r'\D');

int _digitsBefore(String text, int offset) {
  if (offset < 0) return 0;
  final end = offset > text.length ? text.length : offset;
  var count = 0;
  for (var i = 0; i < end; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 48 && unit <= 57) count++;
  }
  return count;
}

int _offsetAfterDigits(String formatted, int digitCount) {
  if (digitCount <= 0) return 0;
  var seen = 0;
  for (var i = 0; i < formatted.length; i++) {
    final unit = formatted.codeUnitAt(i);
    if (unit >= 48 && unit <= 57) {
      seen++;
      if (seen == digitCount) return i + 1;
    }
  }
  return formatted.length;
}
