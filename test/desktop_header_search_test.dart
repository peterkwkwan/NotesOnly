import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/features/shell/desktop_chrome.dart';

void main() {
  test('desktop search hotkey is meta on Apple, control elsewhere', () {
    expect(desktopSearchUsesMetaModifier(TargetPlatform.macOS), isTrue);
    expect(desktopSearchUsesMetaModifier(TargetPlatform.iOS), isTrue);
    expect(desktopSearchUsesMetaModifier(TargetPlatform.linux), isFalse);
    expect(desktopSearchUsesMetaModifier(TargetPlatform.windows), isFalse);
    expect(desktopSearchUsesMetaModifier(TargetPlatform.android), isFalse);

    expect(desktopSearchShortcutLabel(TargetPlatform.macOS), '⌘ K');
    expect(desktopSearchShortcutLabel(TargetPlatform.linux), 'Ctrl+K');
  });
}
