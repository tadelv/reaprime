import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/wake_schedule.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

/// Manages user presence detection, auto-sleep timeout, and scheduled wake.
///
/// Three concerns:
/// 1. **Heartbeat** — event-driven user presence signal, forwarded to DE1 with
///    30-second throttling.
/// 2. **Sleep timeout** — auto-sleep after configurable timeout with no
///    heartbeat.
/// 3. **Scheduled wake** — periodically checks schedules and wakes sleeping
///    machine at matching times.
class PresenceController {
  final De1Controller _de1Controller;
  final SettingsController _settingsController;
  final Logger _log = Logger('PresenceController');

  /// Optional clock function for testing. Returns the current time.
  DateTime Function() _clock;

  /// Allows tests to change the clock after construction.
  set clockOverride(DateTime Function() clock) => _clock = clock;

  // --- Internal state ---
  De1Interface? _de1;
  MachineState? _currentMachineState;
  StreamSubscription<De1Interface?>? _de1Subscription;
  StreamSubscription<MachineSnapshot>? _snapshotSubscription;

  /// Throttle: minimum interval between sendUserPresent() calls.
  static const Duration _presenceThrottle = Duration(seconds: 30);
  DateTime? _lastPresenceSent;

  /// Sleep timeout timer.
  Timer? _sleepTimer;

  /// Schedule checker periodic timer.
  Timer? _scheduleTimer;

  /// Tracks which schedule IDs have fired in the current minute to prevent
  /// re-triggering.
  final Set<String> _firedScheduleIds = {};
  int? _lastCheckedMinute;

  PresenceController({
    required De1Controller de1Controller,
    required SettingsController settingsController,
    DateTime Function()? clock,
  })  : _de1Controller = de1Controller,
        _settingsController = settingsController,
        _clock = clock ?? (() => DateTime.now());

  /// Subscribe to DE1 connection stream, start schedule checker timer,
  /// listen to settings changes.
  void initialize() {
    _de1Subscription = _de1Controller.de1.listen(_onDe1Changed);
    _settingsController.addListener(_onSettingsChanged);
    _startScheduleChecker();
  }

  /// Clean up all subscriptions and timers.
  void dispose() {
    _de1Subscription?.cancel();
    _de1Subscription = null;
    _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _settingsController.removeListener(_onSettingsChanged);
  }

  /// Called by REST API and NavigatorObserver to signal user presence.
  ///
  /// Returns the number of seconds remaining on the sleep timeout, or -1 if
  /// presence is not enabled or no DE1 is connected.
  int heartbeat() {
    if (!_settingsController.userPresenceEnabled || _de1 == null) {
      return -1;
    }

    // Forward sendUserPresent to DE1 with throttling
    _sendPresenceThrottled();

    // Reset the sleep timeout timer
    _resetSleepTimer();

    return _secondsRemaining();
  }

  // ---------------------------------------------------------------------------
  // DE1 connection handling
  // ---------------------------------------------------------------------------

  void _onDe1Changed(De1Interface? de1) {
    if (de1 == _de1) return;

    // Clean up previous connection
    _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _currentMachineState = null;
    _lastPresenceSent = null;

    _de1 = de1;

    if (de1 != null) {
      _log.fine('DE1 connected, subscribing to snapshots');
      _snapshotSubscription = de1.currentSnapshot.listen(_onSnapshot);
    } else {
      _log.fine('DE1 disconnected, cancelling sleep timer');
    }
  }

  void _onSnapshot(MachineSnapshot snapshot) {
    _currentMachineState = snapshot.state.state;
  }

  // ---------------------------------------------------------------------------
  // Settings change handling
  // ---------------------------------------------------------------------------

  void _onSettingsChanged() {
    // If sleep timeout changed, reset the timer with the new value
    if (_de1 != null &&
        _settingsController.userPresenceEnabled &&
        _settingsController.sleepTimeoutMinutes > 0) {
      _resetSleepTimer();
    } else {
      _sleepTimer?.cancel();
      _sleepTimer = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Presence throttling
  // ---------------------------------------------------------------------------

  void _sendPresenceThrottled() {
    final now = _clock();
    if (_lastPresenceSent != null &&
        now.difference(_lastPresenceSent!) < _presenceThrottle) {
      _log.fine('Throttled sendUserPresent');
      return;
    }

    _lastPresenceSent = now;
    _de1?.sendUserPresent().catchError((e) {
      _log.warning('Failed to send user present: $e');
    });
  }

  // ---------------------------------------------------------------------------
  // Sleep timeout
  // ---------------------------------------------------------------------------

  void _resetSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;

    final timeoutMinutes = _settingsController.sleepTimeoutMinutes;
    if (timeoutMinutes <= 0) {
      return;
    }

    _sleepTimer = Timer(
      Duration(minutes: timeoutMinutes),
      _onSleepTimeout,
    );
  }

  void _onSleepTimeout() {
    if (_de1 == null) return;

    // If machine is in an active state, restart the timer instead of sleeping
    if (_isActiveState(_currentMachineState)) {
      _log.info(
          'Sleep timeout fired but machine is in active state ($_currentMachineState), restarting timer');
      _resetSleepTimer();
      return;
    }

    // If machine is in idle or schedIdle, put it to sleep
    if (_currentMachineState == MachineState.idle ||
        _currentMachineState == MachineState.schedIdle) {
      _log.info('Sleep timeout fired, putting machine to sleep');
      _de1!.requestState(MachineState.sleeping).catchError((e) {
        _log.warning('Failed to request sleep: $e');
      });
    }
  }

  /// Returns true for machine states where we should NOT auto-sleep.
  bool _isActiveState(MachineState? state) {
    if (state == null) return false;
    switch (state) {
      case MachineState.espresso:
      case MachineState.steam:
      case MachineState.hotWater:
      case MachineState.flush:
      case MachineState.cleaning:
      case MachineState.descaling:
      case MachineState.fwUpgrade:
        return true;
      default:
        return false;
    }
  }

  int _secondsRemaining() {
    if (_sleepTimer == null || !_sleepTimer!.isActive) {
      return -1;
    }
    // We cannot query Timer for remaining time directly, so we estimate.
    // The timer was started with `sleepTimeoutMinutes` and we know when we
    // last reset it. However, Timer doesn't expose remaining time.
    // Return the configured timeout in seconds as an approximation.
    final timeoutMinutes = _settingsController.sleepTimeoutMinutes;
    if (timeoutMinutes <= 0) return -1;
    return timeoutMinutes * 60;
  }

  // ---------------------------------------------------------------------------
  // Scheduled wake
  // ---------------------------------------------------------------------------

  void _startScheduleChecker() {
    _scheduleTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkSchedules(),
    );
  }

  void _checkSchedules() {
    if (_de1 == null) return;
    if (_currentMachineState != MachineState.sleeping) return;

    final now = _clock();
    final currentMinute = now.hour * 60 + now.minute;

    // Reset fired IDs when the minute changes
    if (_lastCheckedMinute != null && _lastCheckedMinute != currentMinute) {
      _firedScheduleIds.clear();
    }
    _lastCheckedMinute = currentMinute;

    final schedulesJson = _settingsController.wakeSchedules;
    if (schedulesJson.isEmpty || schedulesJson == '[]') return;

    try {
      final schedules = WakeSchedule.deserializeList(schedulesJson);
      for (final schedule in schedules) {
        if (!schedule.enabled) continue;
        if (_firedScheduleIds.contains(schedule.id)) continue;

        if (schedule.matchesTime(now)) {
          _log.info(
              'Schedule ${schedule.id} matched at ${now.hour}:${now.minute}, waking machine');
          _firedScheduleIds.add(schedule.id);
          _de1!.requestState(MachineState.schedIdle).catchError((e) {
            _log.warning('Failed to request schedIdle: $e');
          });
          break; // One wake per check cycle
        }
      }
    } catch (e) {
      _log.warning('Failed to parse wake schedules: $e');
    }
  }
}
