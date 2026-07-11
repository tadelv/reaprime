import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/led_strip.dart';

void main() {
  group('MockBengle LED strip', () {
    test('initial state is all-off', () async {
      final bengle = MockBengle();
      final state = await bengle.getLedStripState();
      expect(state.frontStrip.sleeping, Color16.off);
      expect(state.frontStrip.awake, Color16.off);
      expect(state.backStrip.sleeping, Color16.off);
      expect(state.backStrip.awake, Color16.off);
      expect(state.frontSwitch.sleeping, Color16.off);
      expect(state.frontSwitch.awake, Color16.off);
    });

    test('setLedStrip stores and getLedStripState returns the same state',
        () async {
      final bengle = MockBengle();
      final state = LedStripState(
        frontStrip: ZoneLedState(
            sleeping: const Color16(65535, 32768, 0),
            awake: const Color16(0, 65535, 32768)),
        backStrip: ZoneLedState(
            sleeping: const Color16(10, 20, 30), awake: Color16.off),
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
      expect(emitted[0].frontStrip.sleeping, Color16.off);

      await bengle.setLedStrip(const LedStripState(
        frontStrip: ZoneLedState(
            sleeping: Color16(128, 0, 0), awake: Color16.off),
        backStrip: ZoneLedState(
            sleeping: Color16.off, awake: Color16(0, 255, 0)),
      ));
      expect(emitted, hasLength(2));
      expect(emitted[1].frontStrip.sleeping, const Color16(128, 0, 0));
      expect(emitted[1].backStrip.awake, const Color16(0, 255, 0));
    });

    test('commitLedStrip snapshots cache, resetLedStrip restores it', () async {
      final bengle = MockBengle();
      expect(await bengle.getLedStripState(),
          const LedStripState()); // all-off

      // Write something and commit.
      final state1 = LedStripState(
        frontStrip: ZoneLedState(
            sleeping: const Color16(65535, 0, 0), awake: Color16.off),
      );
      await bengle.setLedStrip(state1);
      await bengle.commitLedStrip();

      // Overwrite with something else.
      await bengle.setLedStrip(const LedStripState());

      // Reset — should be back to state1.
      await bengle.resetLedStrip();
      final after = await bengle.getLedStripState();
      expect(after, state1);
    });

    test('resetLedStrip without commit is a no-op (restores all-off)', () async {
      final bengle = MockBengle();
      // Write without commit.
      await bengle.setLedStrip(LedStripState(
        frontStrip: ZoneLedState(
            sleeping: const Color16(65535, 0, 0), awake: Color16.off),
      ));
      // Reset restores the empty committed state.
      await bengle.resetLedStrip();
      final after = await bengle.getLedStripState();
      expect(after, const LedStripState());
    });

    test('previewLedColor / clearLedPreview are no-ops on the mock', () async {
      // No live strip to preview — neither call may throw or disturb the
      // stored config (real HW: live registers only, cache untouched).
      final bengle = MockBengle();
      final before = await bengle.getLedStripState();

      await bengle.previewLedColor(
          const Color16(65535, 0, 0), const Color16(0, 0, 65535));
      await bengle.clearLedPreview();

      expect(await bengle.getLedStripState(), before);
    });
  });
}
