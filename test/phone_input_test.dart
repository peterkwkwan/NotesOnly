import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/features/clients/phone_field.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

void main() {
  test('Hong Kong national input formats and stores E.164', () {
    final typed = resolvePhoneInput('91234567');
    expect(typed.iso, IsoCode.HK);
    expect(typed.national, '9123 4567');
    expect(typed.e164, '+85291234567');

    final partial = resolvePhoneInput('9123');
    expect(partial.national, '9123');
    expect(partial.e164, '+8529123');

    final legacy = resolvePhoneInput('11234951');
    expect(legacy.e164, '+85211234951');

    expect(resolvePhoneInput('').e164, isEmpty);
  });

  test('a leading calling code selects that country', () {
    final hk = resolvePhoneInput('+852 9123 4567');
    expect(hk.iso, IsoCode.HK);
    expect(hk.national, '9123 4567');
    expect(hk.e164, '+85291234567');

    final us = resolvePhoneInput('+1 202 555 0119');
    expect(us.iso, IsoCode.US);
    expect(us.national, '(202) 555-0119');
    expect(us.e164, '+12025550119');

    final gb = resolvePhoneInput('+44 20 7946 0958', iso: IsoCode.HK);
    expect(gb.iso, IsoCode.GB);
    expect(gb.national, '20 7946 0958');
    expect(gb.e164, '+442079460958');

    final incomplete = resolvePhoneInput('+8');
    expect(incomplete.iso, IsoCode.HK);
    expect(incomplete.e164, isEmpty);

    final usLocal = resolvePhoneInput('2025550119', iso: IsoCode.US);
    expect(usLocal.national, '(202) 555-0119');
    expect(usLocal.e164, '+12025550119');
  });

  test('display keeps a legacy local number and spaces an E.164 value', () {
    expect(displayPhone('11234951'), '11234951');
    expect(displayPhone('+85291234567'), '+852 9123 4567');
  });
}
