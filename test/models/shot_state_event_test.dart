import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/shot_state_event.dart';
import 'package:reaprime/src/models/device/machine.dart';

void main() {
  group('ShotDecision', () {
    test('serializes kind, reason, details and data', () {
      const decision = ShotDecision(
        kind: ShotDecisionKind.stop,
        reason: ShotDecisionReason.targetWeight,
        details: 'Target weight 36.0g reached',
        data: {'targetYield': 36.0, 'projectedWeight': 36.4},
      );

      expect(decision.toJson(), {
        'kind': 'stop',
        'reason': 'targetWeight',
        'details': 'Target weight 36.0g reached',
        'data': {'targetYield': 36.0, 'projectedWeight': 36.4},
      });
    });

    test('serializes null details and data explicitly', () {
      const decision = ShotDecision(
        kind: ShotDecisionKind.advance,
        reason: ShotDecisionReason.profileAdvance,
      );

      expect(decision.toJson(), {
        'kind': 'advance',
        'reason': 'profileAdvance',
        'details': null,
        'data': null,
      });
    });
  });

  group('ShotStateEvent', () {
    test('idle factory produces an idle state frame', () {
      final event = ShotStateEvent.idle();

      expect(event.event, 'state');
      expect(event.state, ShotState.idle);
      expect(event.shotId, isNull);
      expect(event.decision, isNull);
      expect(event.scaleConnected, isFalse);
      expect(event.scaleLost, isFalse);
      expect(event.machineHasAutonomousSAW, isFalse);
    });

    test('serializes a state frame with a fixed schema', () {
      final event = ShotStateEvent(
        event: 'state',
        timestamp: DateTime.utc(2026, 6, 17, 10, 0),
        shotId: 'shot-1',
        state: ShotState.pouring,
        machineState: MachineState.espresso,
        machineSubstate: MachineSubstate.pouring,
        profileFrame: 2,
        scaleConnected: true,
        scaleLost: false,
        machineHasAutonomousSAW: false,
      );

      expect(event.toJson(), {
        'event': 'state',
        'timestamp': '2026-06-17T10:00:00.000Z',
        'shotId': 'shot-1',
        'state': 'pouring',
        'machineState': 'espresso',
        'machineSubstate': 'pouring',
        'profileFrame': 2,
        'scaleConnected': true,
        'scaleLost': false,
        'machineHasAutonomousSAW': false,
        'decision': null,
      });
    });

    test('serializes a decision frame with nested decision', () {
      final event = ShotStateEvent(
        event: 'decision',
        timestamp: DateTime.utc(2026, 6, 17, 10, 0, 5),
        shotId: 'shot-1',
        state: ShotState.pouring,
        machineState: MachineState.espresso,
        machineSubstate: MachineSubstate.pouring,
        profileFrame: 2,
        scaleConnected: true,
        scaleLost: false,
        machineHasAutonomousSAW: false,
        decision: const ShotDecision(
          kind: ShotDecisionKind.stop,
          reason: ShotDecisionReason.targetWeight,
          details: 'Target weight reached',
        ),
      );

      final json = event.toJson();
      expect(json['event'], 'decision');
      expect(json['decision'], {
        'kind': 'stop',
        'reason': 'targetWeight',
        'details': 'Target weight reached',
        'data': null,
      });
    });
  });
}
