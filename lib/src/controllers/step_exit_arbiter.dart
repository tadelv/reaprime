import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/profile.dart';

/// Decides whether the tablet should send `skipStep` on a mixed step
/// (both weight exit and firmware exit conditions), or defer to let
/// firmware handle the transition.
///
/// On each snapshot where projected weight exceeds the step's weight
/// threshold, [evaluate] checks how close the current sensor reading is
/// to the firmware exit threshold:
///
/// - **Far away** → `fire` immediately (no race risk).
/// - **Near** → defer up to [maxDeferralFrames], checking the trend.
///   If the sensor is trending toward the threshold, firmware might fire
///   on its own — wait. If not trending, fire sooner.
/// - **Past threshold** → defer once (firmware should fire imminently).
/// - **Max deferral reached** → `fire` regardless (cap the wait).
///
/// Created per-shot alongside [ShotSequencer]. Call [reset] at shot start
/// and [onFrameAdvanced] when `profileFrame` changes.
class StepExitArbiter {
  static final _log = Logger('StepExitArbiter');

  /// Maximum frames to defer before firing skipStep regardless.
  /// At ~10 Hz DE1 snapshot rate, 3 frames ≈ 300 ms of deferral.
  static const int maxDeferralFrames = 3;

  /// If pressure is within this many bar of the exit threshold,
  /// the firmware exit is "near" and we enter deferral.
  static const double pressureProximityAbsolute = 1.5; // bar

  /// If flow is within this many ml/s of the exit threshold,
  /// the firmware exit is "near" and we enter deferral.
  static const double flowProximityAbsolute = 0.8; // ml/s

  final Map<int, _DeferralState> _deferrals = {};

  StepExitArbiter();

  /// Evaluate whether to fire or defer a tablet `skipStep` for a mixed
  /// step (weight exit reached, firmware exit also present).
  ///
  /// [profileFrame] is the current step index from the machine snapshot.
  /// [exit] is the firmware exit condition on this step.
  /// [currentPressure] and [currentFlow] are the live sensor readings.
  StepExitVerdict evaluate({
    required int profileFrame,
    required StepExitCondition exit,
    required double currentPressure,
    required double currentFlow,
  }) {
    // No-op firmware exit (e.g. pressure over 0) — treat as weight-only.
    if (exit.value <= 0) {
      _log.fine(
        'Frame $profileFrame: firmware exit value ${exit.value} ≤ 0, '
        'treating as weight-only.',
      );
      return StepExitVerdict.fire;
    }

    final sensorValue = switch (exit.type) {
      ExitType.pressure => currentPressure,
      ExitType.flow => currentFlow,
    };

    // Distance: how far the sensor is from triggering the firmware exit.
    // Positive = hasn't triggered yet.
    final distance = switch (exit.condition) {
      ExitCondition.over => exit.value - sensorValue,
      ExitCondition.under => sensorValue - exit.value,
    };

    // Sensor already past threshold — firmware should fire imminently.
    // Defer once to give it a chance.
    if (distance <= 0) {
      final deferral = _deferrals.putIfAbsent(
        profileFrame,
        () => _DeferralState(),
      );
      deferral.record(sensorValue);
      if (deferral.frameCount >= maxDeferralFrames) {
        _log.info(
          'Frame $profileFrame: sensor past firmware threshold '
          '(distance=$distance) for $maxDeferralFrames frames — firing.',
        );
        return StepExitVerdict.fire;
      }
      _log.fine(
        'Frame $profileFrame: sensor past firmware threshold '
        '(distance=$distance), deferring '
        '(${deferral.frameCount}/$maxDeferralFrames).',
      );
      return StepExitVerdict.defer;
    }

    final proximityThreshold = switch (exit.type) {
      ExitType.pressure => pressureProximityAbsolute,
      ExitType.flow => flowProximityAbsolute,
    };

    // Far from threshold — no race risk.
    if (distance > proximityThreshold) {
      _log.info(
        'Frame $profileFrame: firmware exit far '
        '(distance=$distance > $proximityThreshold) — firing skipStep.',
      );
      return StepExitVerdict.fire;
    }

    // Near threshold — enter deferral tracking.
    final deferral = _deferrals.putIfAbsent(
      profileFrame,
      () => _DeferralState(),
    );
    deferral.record(sensorValue);

    if (deferral.frameCount >= maxDeferralFrames) {
      _log.info(
        'Frame $profileFrame: max deferral ($maxDeferralFrames frames) '
        'reached — firing skipStep.',
      );
      return StepExitVerdict.fire;
    }

    if (deferral.isTrending(exit.condition)) {
      _log.fine(
        'Frame $profileFrame: near firmware threshold '
        '(distance=$distance) and trending — deferring '
        '(${deferral.frameCount}/$maxDeferralFrames).',
      );
      return StepExitVerdict.defer;
    }

    // Not trending toward threshold — firmware unlikely to fire.
    _log.info(
      'Frame $profileFrame: near firmware threshold '
      '(distance=$distance) but NOT trending — firing skipStep.',
    );
    return StepExitVerdict.fire;
  }

  /// Notify that the machine's profileFrame has changed.
  /// Clears any deferral state for frames other than [newFrame].
  void onFrameAdvanced(int newFrame) {
    _deferrals.removeWhere((frame, _) => frame != newFrame);
  }

  /// Reset all state. Call at shot start.
  void reset() {
    _deferrals.clear();
  }
}

/// The arbiter's recommendation for a mixed-step weight exit.
enum StepExitVerdict {
  /// Send `skipStep` now.
  fire,

  /// Wait — firmware exit may fire on its own.
  defer,
}

class _DeferralState {
  int frameCount = 0;
  final List<double> readings = [];

  void record(double sensorValue) {
    readings.add(sensorValue);
    frameCount++;
  }

  /// Whether the latest reading is moving toward the exit condition
  /// threshold compared to the previous reading.
  ///
  /// On the first sample (no prior reading), assumes trending
  /// (conservative: gives firmware the benefit of the doubt).
  bool isTrending(ExitCondition condition) {
    if (readings.length < 2) return true;
    final prev = readings[readings.length - 2];
    final curr = readings.last;
    return switch (condition) {
      ExitCondition.over => curr > prev,
      ExitCondition.under => curr < prev,
    };
  }
}
