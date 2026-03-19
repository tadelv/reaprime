import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/foreground_service.dart';

void main() {
  group('ForegroundServiceGraceTimer', () {
    late ForegroundServiceGraceTimer timer;
    bool stopCalled = false;
    bool startCalled = false;

    setUp(() {
      stopCalled = false;
      startCalled = false;
      timer = ForegroundServiceGraceTimer(
        gracePeriod: Duration(minutes: 5),
        onStop: () async { stopCalled = true; },
        onStart: () async { startCalled = true; },
      );
    });

    tearDown(() {
      timer.dispose();
    });

    test('does not stop immediately on disconnect', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        expect(stopCalled, isFalse);
      });
    });

    test('stops after grace period expires', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        async.elapse(Duration(minutes: 5, seconds: 1));
        expect(stopCalled, isTrue);
      });
    });

    test('does not stop before grace period expires', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        async.elapse(Duration(minutes: 4));
        expect(stopCalled, isFalse);
      });
    });

    test('cancels stop if machine reconnects during grace period', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        async.elapse(Duration(minutes: 2));
        timer.onMachineConnected();
        async.elapse(Duration(minutes: 5));
        expect(stopCalled, isFalse);
      });
    });

    test('does not call onStart on connect if service was never stopped', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        async.elapse(Duration(minutes: 2));
        timer.onMachineConnected();
        expect(startCalled, isFalse);
      });
    });

    test('restarts service on connect if previously stopped', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        async.elapse(Duration(minutes: 6));
        expect(stopCalled, isTrue);

        startCalled = false;
        timer.onMachineConnected();
        expect(startCalled, isTrue);
      });
    });
  });
}
