import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/led_strip.dart';

void main() {
  group('MockBengle LED strip', () {
    test('initial state is all-off', () async {
      final bengle = MockBengle();
      final state = await bengle.getLedStripState();
      expect(state.frontRed, 0);
      expect(state.frontGreen, 0);
      expect(state.frontBlue, 0);
      expect(state.backRed, 0);
      expect(state.backGreen, 0);
      expect(state.backBlue, 0);
    });

    test('setLedStrip stores and getLedStripState returns the same state',
        () async {
      final bengle = MockBengle();
      final state = LedStripState(
        frontRed: 255,
        frontGreen: 128,
        frontBlue: 0,
        backRed: 10,
        backGreen: 20,
        backBlue: 30,
      );
      await bengle.setLedStrip(state);
      final read = await bengle.getLedStripState();
      expect(read, state);
    });

    test('ledStripState stream emits set values', () async {
      final bengle = MockBengle();
      final emitted = <LedStripState>[];
      final sub = bengle.ledStripState.listen(emitted.add);
      addTearDown(sub.cancel);

      // Seeded initial value delivered on first microtask.
      await Future(() {}); // let seed propagate
      expect(emitted, hasLength(1));
      expect(emitted[0].frontRed, 0);

      await bengle.setLedStrip(const LedStripState(
        frontRed: 128,
        backGreen: 255,
      ));
      expect(emitted, hasLength(2));
      expect(emitted[1].frontRed, 128);
      expect(emitted[1].backGreen, 255);
    });
  });
}
