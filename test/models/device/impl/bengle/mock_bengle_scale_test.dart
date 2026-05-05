import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';

void main() {
  group('MockBengle integrated scale', () {
    late MockBengle bengle;

    setUp(() async {
      bengle = MockBengle();
      await bengle.onConnect();
    });

    tearDown(() async {
      await bengle.onDisconnect();
    });

    test('emits weightSnapshot after connect', () async {
      final snapshot = await bengle.weightSnapshot.first
          .timeout(const Duration(seconds: 2));
      expect(snapshot.batteryLevel, 100);
      expect(snapshot.weight, isA<double>());
    });

    test('weight rises during simulated espresso shot', () async {
      final pre = await bengle.weightSnapshot.first
          .timeout(const Duration(seconds: 2));

      await bengle.requestState(MachineState.espresso);
      await Future.delayed(const Duration(seconds: 2));
      await bengle.requestState(MachineState.idle);

      final post = await bengle.weightSnapshot.first
          .timeout(const Duration(seconds: 2));
      expect(post.weight, greaterThan(pre.weight));
    });

    test('tareIntegratedScale zeroes the next emit', () async {
      await bengle.requestState(MachineState.espresso);
      await Future.delayed(const Duration(seconds: 1));
      await bengle.requestState(MachineState.idle);

      await bengle.weightSnapshot.first;
      await bengle.tareIntegratedScale();
      final next = await bengle.weightSnapshot.first
          .timeout(const Duration(seconds: 2));
      expect(next.weight.abs(), lessThan(0.01));
    });

    test('disconnect closes the snapshot stream', () async {
      await bengle.onDisconnect();
      // Subscribing post-close: BehaviorSubject replays its last buffered
      // value (if any) then immediately delivers `done`. Either way the
      // stream completes — `toList()` returns within the timeout. If the
      // close didn't propagate, this would hang and time out.
      final all = await bengle.weightSnapshot
          .toList()
          .timeout(const Duration(seconds: 1));
      expect(all, isA<List<ScaleSnapshot>>());
    });
  });
}
