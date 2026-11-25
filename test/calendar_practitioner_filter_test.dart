import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/features/calendar/calendar_practitioner_filter.dart';

void main() {
  group('matchesCalendarFilter', () {
    test('empty filter shows all', () {
      expect(
        matchesCalendarFilter(
          filterUids: {},
          practitionerUid: 'a',
          selfUid: 'me',
        ),
        isTrue,
      );
    });

    test('empty appointment uid counts as self', () {
      expect(
        matchesCalendarFilter(
          filterUids: {'me'},
          practitionerUid: '',
          selfUid: 'me',
        ),
        isTrue,
      );
      expect(
        matchesCalendarFilter(
          filterUids: {'other'},
          practitionerUid: '',
          selfUid: 'me',
        ),
        isFalse,
      );
    });

    test('matches selected uid', () {
      expect(
        matchesCalendarFilter(
          filterUids: {'a', 'b'},
          practitionerUid: 'b',
          selfUid: 'me',
        ),
        isTrue,
      );
      expect(
        matchesCalendarFilter(
          filterUids: {'a'},
          practitionerUid: 'b',
          selfUid: 'me',
        ),
        isFalse,
      );
    });
  });

  test('parse / encode round-trip', () {
    expect(parseCalendarFilterUids('a, b,,c'), {'a', 'b', 'c'});
    expect(encodeCalendarFilterUids({'x', 'y'}), anyOf('x,y', 'y,x'));
    expect(calendarFilterUidsKey('org1', 'u1'), 'calendar_filter_uids__org1__u1');
  });
}
