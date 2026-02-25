import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:rxdart/subjects.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum DisplayBrightness { normal, dimmed }

class DisplayPlatformSupport {
  final bool brightness;
  final bool wakeLock;

  const DisplayPlatformSupport({
    required this.brightness,
    required this.wakeLock,
  });

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'wakeLock': wakeLock,
      };
}

class DisplayState {
  final bool wakeLockEnabled;
  final bool wakeLockOverride;
  final DisplayBrightness brightness;
  final DisplayPlatformSupport platformSupported;

  const DisplayState({
    required this.wakeLockEnabled,
    required this.wakeLockOverride,
    required this.brightness,
    required this.platformSupported,
  });

  DisplayState copyWith({
    bool? wakeLockEnabled,
    bool? wakeLockOverride,
    DisplayBrightness? brightness,
    DisplayPlatformSupport? platformSupported,
  }) =>
      DisplayState(
        wakeLockEnabled: wakeLockEnabled ?? this.wakeLockEnabled,
        wakeLockOverride: wakeLockOverride ?? this.wakeLockOverride,
        brightness: brightness ?? this.brightness,
        platformSupported: platformSupported ?? this.platformSupported,
      );

  Map<String, dynamic> toJson() => {
        'wakeLockEnabled': wakeLockEnabled,
        'wakeLockOverride': wakeLockOverride,
        'brightness': brightness.name,
        'platformSupported': platformSupported.toJson(),
      };
}

/// Manages screen wake-lock and brightness.
///
/// Two concerns:
/// 1. **Wake-lock** — auto-managed based on machine state (enabled when
///    connected and not sleeping, released on sleep/disconnect). Skins can
///    override via [requestWakeLock] / [releaseWakeLock].
/// 2. **Brightness** — skin-initiated dim/restore. Safety-net auto-restore
///    when machine transitions from sleeping to idle/schedIdle.
class DisplayController {
  final De1Controller _de1Controller;
  final Logger _log = Logger('DisplayController');

  // --- Platform support detection ---
  late final DisplayPlatformSupport _platformSupport;

  // --- State broadcasting ---
  late final BehaviorSubject<DisplayState> _stateSubject;
  Stream<DisplayState> get state => _stateSubject.stream;
  DisplayState get currentState => _stateSubject.value;

  // --- Internal state ---
  De1Interface? _de1;
  MachineState? _currentMachineState;
  StreamSubscription<De1Interface?>? _de1Subscription;
  StreamSubscription<MachineSnapshot>? _snapshotSubscription;
  bool _wakeLockOverride = false;

  DisplayController({required De1Controller de1Controller})
      : _de1Controller = de1Controller {
    _platformSupport = DisplayPlatformSupport(
      brightness: Platform.isAndroid || Platform.isIOS || Platform.isMacOS,
      wakeLock: true, // wakelock_plus supports all platforms
    );

    _stateSubject = BehaviorSubject.seeded(DisplayState(
      wakeLockEnabled: false,
      wakeLockOverride: false,
      brightness: DisplayBrightness.normal,
      platformSupported: _platformSupport,
    ));
  }

  void initialize() {
    _de1Subscription = _de1Controller.de1.listen(_onDe1Changed);
  }

  void dispose() {
    _de1Subscription?.cancel();
    _de1Subscription = null;
    _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    _stateSubject.close();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Dim the screen to a low brightness level.
  Future<void> dim() async {
    if (!_platformSupport.brightness) return;
    try {
      await ScreenBrightness().setApplicationScreenBrightness(0.05);
      _updateState(brightness: DisplayBrightness.dimmed);
      _log.fine('Screen dimmed');
    } catch (e) {
      _log.warning('Failed to dim screen: $e');
    }
  }

  /// Restore screen brightness to system default.
  Future<void> restore() async {
    if (!_platformSupport.brightness) return;
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
      _updateState(brightness: DisplayBrightness.normal);
      _log.fine('Screen brightness restored');
    } catch (e) {
      _log.warning('Failed to restore brightness: $e');
    }
  }

  /// Request wake-lock override (skin wants screen always on).
  Future<void> requestWakeLock() async {
    _wakeLockOverride = true;
    await _applyWakeLock(true);
    _updateState(wakeLockOverride: true);
    _log.fine('Wake-lock override requested');
  }

  /// Release wake-lock override (return to auto-managed).
  Future<void> releaseWakeLock() async {
    _wakeLockOverride = false;
    _updateState(wakeLockOverride: false);
    // Re-evaluate: if machine is sleeping/disconnected, release wake-lock
    await _evaluateWakeLock();
    _log.fine('Wake-lock override released');
  }

  // ---------------------------------------------------------------------------
  // DE1 connection handling
  // ---------------------------------------------------------------------------

  void _onDe1Changed(De1Interface? de1) {
    if (de1 == _de1) return;

    _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    _currentMachineState = null;

    _de1 = de1;

    if (de1 != null) {
      _log.fine('DE1 connected, subscribing to snapshots for display mgmt');
      _snapshotSubscription = de1.currentSnapshot.listen(_onSnapshot);
    } else {
      _log.fine('DE1 disconnected, releasing wake-lock');
      _evaluateWakeLock();
    }
  }

  void _onSnapshot(MachineSnapshot snapshot) {
    final previousState = _currentMachineState;
    _currentMachineState = snapshot.state.state;

    // Auto-restore brightness when machine wakes from sleep
    if (previousState == MachineState.sleeping &&
        (_currentMachineState == MachineState.idle ||
            _currentMachineState == MachineState.schedIdle)) {
      if (currentState.brightness == DisplayBrightness.dimmed) {
        _log.info('Machine woke from sleep, auto-restoring brightness');
        unawaited(restore());
      }
    }

    unawaited(_evaluateWakeLock());
  }

  // ---------------------------------------------------------------------------
  // Wake-lock logic
  // ---------------------------------------------------------------------------

  Future<void> _evaluateWakeLock() async {
    // Override always wins
    if (_wakeLockOverride) {
      await _applyWakeLock(true);
      return;
    }

    // Auto-manage: enable if connected and not sleeping
    final shouldEnable =
        _de1 != null && _currentMachineState != MachineState.sleeping;
    await _applyWakeLock(shouldEnable);
  }

  Future<void> _applyWakeLock(bool enable) async {
    try {
      if (enable) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
      _updateState(wakeLockEnabled: enable);
    } catch (e) {
      _log.warning('Failed to ${enable ? "enable" : "disable"} wake-lock: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // State management
  // ---------------------------------------------------------------------------

  void _updateState({
    bool? wakeLockEnabled,
    bool? wakeLockOverride,
    DisplayBrightness? brightness,
  }) {
    _stateSubject.add(currentState.copyWith(
      wakeLockEnabled: wakeLockEnabled,
      wakeLockOverride: wakeLockOverride,
      brightness: brightness,
    ));
  }
}
