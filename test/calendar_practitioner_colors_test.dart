import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/features/calendar/calendar_practitioner_colors.dart';
import 'package:pelvi_crm/theme/theme.dart';

void main() {
  const c = PelviPalette.light;

  test('self is pink; roster order is stable', () {
    final me = practitionerColors(
      c: c,
      uid: 'me',
      selfUid: 'me',
      rosterUids: const ['me', 'a', 'b'],
    );
    expect(me.accent, c.pink400);

    final a = practitionerColors(
      c: c,
      uid: 'a',
      selfUid: 'me',
      rosterUids: const ['me', 'a', 'b'],
    );
    final aAgain = practitionerColors(
      c: c,
      uid: 'a',
      selfUid: 'me',
      rosterUids: const ['me', 'a', 'b'],
    );
    expect(a.accent, aAgain.accent);
    expect(a.accent, c.purple400);
  });

  test('unknown uid falls back to hash palette', () {
    final x = practitionerColors(
      c: c,
      uid: 'mystery',
      selfUid: 'me',
      rosterUids: const ['me'],
    );
    final y = practitionerColors(
      c: c,
      uid: 'mystery',
      selfUid: 'me',
      rosterUids: const ['me'],
    );
    expect(x.accent, y.accent);
    expect(x.accent, isNot(c.pink400));
  });
}
