import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/launcher/launcher_view.dart';

void main() {
  group('resolveLauncherSkinSlot', () {
    test('browser hero when WebView unsupported (regardless of serving)', () {
      expect(
        resolveLauncherSkinSlot(
          supportsWebView: false,
          isDegradedAndroid: false,
          isServing: true,
        ),
        LauncherSkinSlot.browserHero,
      );
    });

    test('browser hero when degraded Android (regardless of serving)', () {
      expect(
        resolveLauncherSkinSlot(
          supportsWebView: true,
          isDegradedAndroid: true,
          isServing: true,
        ),
        LauncherSkinSlot.browserHero,
      );
    });

    test('return-to-skin when capable, not degraded, serving', () {
      expect(
        resolveLauncherSkinSlot(
          supportsWebView: true,
          isDegradedAndroid: false,
          isServing: true,
        ),
        LauncherSkinSlot.returnToSkin,
      );
    });

    test('skin-unavailable when capable, not degraded, not serving', () {
      expect(
        resolveLauncherSkinSlot(
          supportsWebView: true,
          isDegradedAndroid: false,
          isServing: false,
        ),
        LauncherSkinSlot.skinUnavailable,
      );
    });
  });
}
