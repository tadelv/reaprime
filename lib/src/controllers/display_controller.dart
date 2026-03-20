import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/charging_logic.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/subjects.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  final int brightness;
  final int requestedBrightness;
  final bool lowBatteryBrightnessActive;
  final DisplayPlatformSupport platformSupported;

  const DisplayState({
    required this.wakeLockEnabled,
    required this.wakeLockOverride,
    required this.brightness,
    required this.requestedBrightness,
    required this.lowBatteryBrightnessActive,
    required this.platformSupported,
  });

  DisplayState copyWith({
    bool? wakeLockEnabled,
    bool? wakeLockOverride,
    int? brightness,
    int? requestedBrightness,
    bool? lowBatteryBrightnessActive,
    DisplayPlatformSupport? platformSupported,
  }) =>
      DisplayState(
        wakeLockEnabled: wakeLockEnabled ?? this.wakeLockEnabled,
        wakeLockOverride: wakeLockOverride ?? this.wakeLockOverride,
        brightness: brightness ?? this.brightness,
        requestedBrightness: requestedBrightness ?? this.requestedBrightness,
        lowBatteryBrightnessActive:
            lowBatteryBrightnessActive ?? this.lowBatteryBrightnessActive,
        platformSupported: platformSupported ?? this.platformSupported,
      );

  Map<String, dynamic> toJson() => {
        'wakeLockEnabled': wakeLockEnabled,
        'wakeLockOverride': wakeLockOverride,
        'brightness': brightness,
        'requestedBrightness': requestedBrightness,
        'lowBatteryBrightnessActive': lowBatteryBrightnessActive,
        'platformSupported': platformSupported.toJson(),
      };
}

/// Manages screen wake-lock and brightness.
///
/// Two concerns:
/// 1. **Wake-lock** — auto-managed based on machine state (enabled when
///    connected and not sleeping, released on sleep/disconnect). Skins can
///    override via [requestWakeLock] / [releaseWakeLock].
/// 2. **Brightness** — 0-100 integer range via [setBrightness]. Value 100
///    resets to OS-managed brightness. Battery-aware cap reduces brightness
///    when battery is low and the setting is enabled.
class DisplayController {
  final De1Controller _de1Controller;
  final SettingsController _settingsController;
  final Logger _log = Logger('DisplayController');

  static const int _lowBatteryThreshold = 30;
  static const int _lowBatteryBrightnessCap = 20;
  static final ScreenBrightness _defaultScreenBrightness = ScreenBrightness();

  // --- Injectable platform operations (for testability) ---
  final Future<void> Function(double) _setBrightness;
  final Future<void> Function() _resetBrightness;
  final Future<void> Function() _enableWakeLock;
  final Future<void> Function() _disableWakeLock;

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

  // --- Brightness state ---
  int _requestedBrightness = 100;
  int _preSleepBrightness = 100;

  // --- Battery brightness cap state ---
  final Stream<ChargingState>? _batteryStateStream;
  StreamSubscription<ChargingState>? _batterySubscription;
  int? _lastBatteryPercent;

  DisplayController({
    required De1Controller de1Controller,
    required SettingsController settingsController,
    Stream<ChargingState>? batteryStateStream,
    Future<void> Function(double)? setBrightness,
    Future<void> Function()? resetBrightness,
    Future<void> Function()? enableWakeLock,
    Future<void> Function()? disableWakeLock,
  })  : _de1Controller = de1Controller,
        _settingsController = settingsController,
        _batteryStateStream = batteryStateStream,
        _setBrightness = setBrightness ??
            _defaultScreenBrightness.setApplicationScreenBrightness,
        _resetBrightness = resetBrightness ??
            _defaultScreenBrightness.resetApplicationScreenBrightness,
        _enableWakeLock = enableWakeLock ?? WakelockPlus.enable,
        _disableWakeLock = disableWakeLock ?? WakelockPlus.disable {
    _platformSupport = DisplayPlatformSupport(
      brightness:
          Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows,
      wakeLock: true, // wakelock_plus supports all platforms
    );

    _stateSubject = BehaviorSubject.seeded(DisplayState(
      wakeLockEnabled: false,
      wakeLockOverride: false,
      brightness: 100,
      requestedBrightness: 100,
      lowBatteryBrightnessActive: false,
      platformSupported: _platformSupport,
    ));
  }

  void initialize() {
    _de1Subscription = _de1Controller.de1.listen(_onDe1Changed);
    _batterySubscription = _batteryStateStream?.listen(_onBatteryChanged);
    _settingsController.addListener(_onSettingsChanged);
  }

  void dispose() {
    _de1Subscription?.cancel();
    _de1Subscription = null;
    _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    _batterySubscription?.cancel();
    _batterySubscription = null;
    _settingsController.removeListener(_onSettingsChanged);
    _stateSubject.close();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Set screen brightness to a value between 0 and 100.
  ///
  /// Value 100 resets to OS-managed brightness (respects auto-brightness).
  /// Values 0-99 set a specific brightness level.
  Future<void> setBrightness(int value) async {
    final clamped = value.clamp(0, 100);
    _requestedBrightness = clamped;
    await _applyBrightness();
  }

  /// Dim the screen to minimum brightness.
  ///
  /// Deprecated: Use [setBrightness] with a value of 5 instead.
  @Deprecated('Use setBrightness(5) instead')
  Future<void> dim() async {
    await setBrightness(5);
  }

  /// Restore screen brightness to system default.
  ///
  /// Deprecated: Use [setBrightness] with a value of 100 instead.
  @Deprecated('Use setBrightness(100) instead')
  Future<void> restore() async {
    await setBrightness(100);
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
  // Brightness logic
  // ---------------------------------------------------------------------------

  Future<void> _applyBrightness() async {
    if (!_platformSupport.brightness) return;

    final effective = _computeEffectiveBrightness();
    final capping = effective < _requestedBrightness;

    try {
      if (effective == 100) {
        await _resetBrightness();
      } else {
        await _setBrightness(effective / 100.0);
      }
      _updateState(
        brightness: effective,
        requestedBrightness: _requestedBrightness,
        lowBatteryBrightnessActive: capping,
      );
      _log.fine(
          'Brightness set to $effective (requested: $_requestedBrightness, capping: $capping)');
    } catch (e) {
      _log.warning('Failed to set brightness: $e');
    }
  }

  int _computeEffectiveBrightness() {
    // No battery stream means desktop — no cap
    if (_batteryStateStream == null) return _requestedBrightness;

    // Setting must be enabled
    if (!_settingsController.lowBatteryBrightnessLimit) {
      return _requestedBrightness;
    }

    // Battery must be below threshold
    if (_lastBatteryPercent != null &&
        _lastBatteryPercent! < _lowBatteryThreshold) {
      return _requestedBrightness.clamp(0, _lowBatteryBrightnessCap);
    }

    return _requestedBrightness;
  }

  void _onBatteryChanged(ChargingState state) {
    _lastBatteryPercent = state.batteryPercent;
    unawaited(_applyBrightness());
  }

  void _onSettingsChanged() {
    unawaited(_applyBrightness());
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

    if (previousState == _currentMachineState) return;

    // Save brightness before sleep; restore when machine wakes
    if (_currentMachineState == MachineState.sleeping) {
      _preSleepBrightness = _requestedBrightness;
    } else if (previousState == MachineState.sleeping &&
        (_currentMachineState == MachineState.idle ||
            _currentMachineState == MachineState.schedIdle)) {
      _log.info('Machine woke from sleep, restoring brightness');
      unawaited(setBrightness(_preSleepBrightness));
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
        await _enableWakeLock();
      } else {
        await _disableWakeLock();
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
    int? brightness,
    int? requestedBrightness,
    bool? lowBatteryBrightnessActive,
  }) {
    _stateSubject.add(currentState.copyWith(
      wakeLockEnabled: wakeLockEnabled,
      wakeLockOverride: wakeLockOverride,
      brightness: brightness,
      requestedBrightness: requestedBrightness,
      lowBatteryBrightnessActive: lowBatteryBrightnessActive,
    ));
  }
}
