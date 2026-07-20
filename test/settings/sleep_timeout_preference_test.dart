import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/sleep_timeout_preference.dart';

void main() {
  group('normalizeSleepTimeoutPreferenceMinutes', () {
    test('preserves values inside 0..240', () {
      expect(normalizeSleepTimeoutPreferenceMinutes(0), 0);
      expect(normalizeSleepTimeoutPreferenceMinutes(30), 30);
      expect(normalizeSleepTimeoutPreferenceMinutes(240), 240);
    });

    test('clamps negative values to 0', () {
      expect(normalizeSleepTimeoutPreferenceMinutes(-1), 0);
      expect(normalizeSleepTimeoutPreferenceMinutes(-100), 0);
    });

    test('clamps oversized values to 240', () {
      expect(normalizeSleepTimeoutPreferenceMinutes(241), 240);
      expect(normalizeSleepTimeoutPreferenceMinutes(999), 240);
    });
  });
}
