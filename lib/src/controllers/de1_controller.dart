import 'dart:async';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/connection/connection_timings.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/forms/hot_water_form.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/models/data/shot_state_event.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:rxdart/subjects.dart';

part 'de1_controller.defaults.dart';

class De1Controller {
  final DeviceController _deviceController;

  Workflow? defaultWorkflow;

  De1Interface? _de1;
  final Logger _log = Logger("De1Controller");

  final BehaviorSubject<De1Interface?> _de1Controller = BehaviorSubject.seeded(
    null,
  );

  Stream<De1Interface?> get de1 => _de1Controller.stream;

  final BehaviorSubject<SteamSettings> _steamDataController =
      BehaviorSubject.seeded(
        SteamSettings(
          targetTemperature: 0,
          flow: 0,
          duration: 0,
        ),
      );

  Stream<SteamSettings> get steamData => _steamDataController.stream;

  final BehaviorSubject<HotWaterData> _hotWaterDataController =
      BehaviorSubject.seeded(
        HotWaterData(
          targetTemperature: 0,
          flow: 0,
          duration: 0,
          volume: 0,
        ),
      );

  Stream<HotWaterData> get hotWaterData => _hotWaterDataController.stream;

  final BehaviorSubject<RinseData> _rinseStream = BehaviorSubject.seeded(
    RinseData(
      duration: 5,
      targetTemperature: 90,
      flow: 2.5,
    ),
  );

  Stream<RinseData> get rinseData => _rinseStream.stream;

  /// Live shot state + decision feed, backing `/ws/v1/machine/shotState`.
  ///
  /// De1StateManager forwards each per-shot ShotSequencer's state transitions
  /// and decisions into here via [publishShotEvent] — the sequencer itself is
  /// recreated every shot and its streams close on dispose, so this long-lived
  /// subject is what WebSocket clients subscribe to. Seeded with an idle frame
  /// so a late joiner never replays a stale mid-shot frame from a previous
  /// shot.
  final BehaviorSubject<ShotStateEvent> _shotStateSubject =
      BehaviorSubject.seeded(ShotStateEvent.idle());

  Stream<ShotStateEvent> get shotState => _shotStateSubject.stream;
  ShotStateEvent get currentShotState => _shotStateSubject.value;

  /// WS-frame trail at FINE; the per-decision INFO/WARNING line is emitted
  /// once by ShotSequencer under the same logger name — don't log it twice.
  static final Logger _shotStateLog = Logger('ShotState');

  void publishShotEvent(ShotStateEvent event) {
    _shotStateLog.fine(
      '[shot ${event.shotId ?? '-'}] ${event.event}: ${event.state.name}'
      '${event.decision != null ? ' (${event.decision!.reason.name})' : ''}',
    );
    if (!_shotStateSubject.isClosed) {
      _shotStateSubject.add(event);
    }
  }

  /// Pre-declared stop intent, so the sequencer can attribute a
  /// machine-reported shot end to the command that caused it. The REST state
  /// handler and the in-app Stop button record intent just before issuing
  /// `requestState(idle)`; when the resulting `pouringDone` arrives the
  /// sequencer consumes it. Anything older than [_stopIntentWindow] is stale —
  /// a leftover stamp from an unrelated request must not label a later,
  /// natural shot end.
  static const Duration _stopIntentWindow = Duration(seconds: 5);
  ShotDecisionReason? _pendingStopIntent;
  DateTime? _pendingStopIntentAt;

  void recordStopIntent(ShotDecisionReason reason) {
    assert(
      reason == ShotDecisionReason.apiStop ||
          reason == ShotDecisionReason.appStop,
      'stop intent must name a command source (apiStop/appStop)',
    );
    _pendingStopIntent = reason;
    _pendingStopIntentAt = clock.now();
  }

  /// Returns the pending intent if one was recorded within [window], and
  /// clears it either way — an intent is attributed at most once.
  ShotDecisionReason? consumeStopIntent({
    Duration window = _stopIntentWindow,
  }) {
    final intent = _pendingStopIntent;
    final at = _pendingStopIntentAt;
    _pendingStopIntent = null;
    _pendingStopIntentAt = null;
    if (intent == null || at == null) return null;
    if (clock.now().difference(at) > window) return null;
    return intent;
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _dataInitialized = false;
  Timer? _shotSettingsDebounce;

  /// Bumped every time `_onDisconnect()` runs. Captured by the
  /// `_shotSettingsUpdate` debounce-timer closure at scheduling
  /// time so a timer that fires after a disconnect can see "the
  /// connection I was scheduled for is gone" and bail out before
  /// calling `connectedDe1()` (which would throw
  /// `DeviceNotConnectedException`). Covers comms-harden #5.
  int _connectionGeneration = 0;

  De1Controller({required DeviceController controller})
    : _deviceController = controller {
    _log.info("checking ${_deviceController.devices}");
  }

  Future<void> connectToDe1(De1Interface de1Interface) async {
    if (de1Interface == _de1) {
      _log.fine("trying to connect to existing de1, exit early");
      return;
    }
    _onDisconnect(); // just in case
    _log.fine("found de1, connecting");
    try {
      await de1Interface.onConnect();
    } catch (e, st) {
      _log.warning(
        'Failed to connect to ${de1Interface.name} '
        '(${de1Interface.deviceId}): $e',
        e,
        st,
      );
      _onDisconnect();
      rethrow;
    }
    _de1 = de1Interface;
    _de1Controller.add(_de1);

    _subscriptions.add(
      _de1!.ready.listen(
        (ready) {
          if (ready) {
            _initializeData();
          }
        },
      ),
    );

    _subscriptions.add(
      _de1!.connectionState.listen(
        (connectionData) {
          switch (connectionData) {
            case ConnectionState.discovered:
              _log.info("device $_de1 discovered");
            case ConnectionState.connecting:
              _log.info("device $_de1 connecting");
            case ConnectionState.connected:
              _log.info("device $_de1 connected");
            case ConnectionState.disconnecting:
              _log.info("device $_de1 disconnecting");
            case ConnectionState.disconnected:
              _log.info("device $_de1 disconnected, resetting");
              _onDisconnect();
          }
        },
      ),
    );
  }

  /// Adopt a device that has already been connected and had [onConnect]
  /// called by [tryQuickConnect]. Skips [onConnect] and wires up stream
  /// subscriptions directly — the inverse of [connectToDe1] minus the
  /// connect call.
  void adoptDevice(De1Interface de1Interface) {
    if (de1Interface == _de1) {
      _log.fine('adoptDevice: already connected to this device, exit early');
      return;
    }
    _onDisconnect();
    _de1 = de1Interface;
    _de1Controller.add(_de1);

    _subscriptions.add(
      _de1!.ready.listen(
        (ready) {
          if (ready) {
            _initializeData();
          }
        },
      ),
    );

    _subscriptions.add(
      _de1!.connectionState.listen(
        (connectionData) {
          switch (connectionData) {
            case ConnectionState.disconnected:
              _log.info('device $_de1 disconnected (adopted), resetting');
              _onDisconnect();
            default:
              break;
          }
        },
      ),
    );
  }

  void _onDisconnect() {
    _log.info("resetting de1");
    _connectionGeneration++;
    _de1 = null;
    _de1Controller.add(_de1);
    _dataInitialized = false;
    _initSettledSubject.add(null);
    _shotSettingsDebounce?.cancel();
    _shotSettingsDebounce = null;
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> _initializeData() async {
    if (_dataInitialized) {
      _log.warning(
        "Data already initialized, skipping (this should only happen once!)",
      );
      return;
    }
    _log.info("Initializing DE1 data for the first time");
    _dataInitialized = true;

    await connectedDe1().shotSettings.first.then(_shotSettingsUpdate);
    _subscriptions.add(
      connectedDe1().shotSettings.listen(
        _shotSettingsUpdate,
      ),
    );
    _log.info(
      "Created shotSettings listener, total subscriptions: ${_subscriptions.length}",
    );
    await _setDe1Defaults();
    _initSettledSubject.add(_connectionGeneration);
  }

  Future<void> _shotSettingsUpdate(De1ShotSettings data) async {
    // Debounce rapid successive calls (e.g., from setSteamFlow +
    // setHotWaterFlow + updateShotSettings). Capture the current
    // generation so a disconnect + cancel race where the timer has
    // already fired but the closure hasn't started awaiting yet still
    // bails out cleanly (comms-harden #5).
    _shotSettingsDebounce?.cancel();
    final generation = _connectionGeneration;
    _shotSettingsDebounce = Timer(
      ConnectionTimings.shotSettingsDebounce,
      () async {
        if (generation != _connectionGeneration || _de1 == null) {
          _log.fine(
            'Shot settings debounce fired after disconnect '
            '(gen=$generation, current=$_connectionGeneration) — skipping',
          );
          return;
        }
        _log.info('Processing shot settings update (debounced)');
        try {
          await _processShotSettingsUpdate(data);
        } on DeviceNotConnectedException catch (e) {
          // Defence in depth: device may have disconnected between the
          // generation check above and any of the awaits in the body.
          _log.fine('Shot settings update aborted by disconnect: $e');
        } on MmrTimeoutException catch (e) {
          // An MMR read inside the readback can time out if the BLE
          // adapter drops mid-sequence. That's functionally the same as
          // a disconnect — don't escalate to a fatal crash.
          _log.warning(
            'Shot settings update MMR read timed out '
            '(treating as disconnect): $e',
          );
        }
      },
    );
  }

  Future<void> _processShotSettingsUpdate(De1ShotSettings data) async {
    var steamFlow = await connectedDe1().getSteamFlow();
    _steamDataController.add(
      SteamSettings(
        duration: data.targetSteamDuration,
        targetTemperature: data.targetSteamTemp,
        flow: steamFlow,
      ),
    );
    var hwFlow = await connectedDe1().getHotWaterFlow();
    _hotWaterDataController.add(
      HotWaterData(
        volume: data.targetHotWaterVolume,
        flow: hwFlow,
        targetTemperature: data.targetHotWaterTemp,
        duration: data.targetHotWaterDuration,
      ),
    );
    {
      var flow = await connectedDe1().getFlushFlow();
      var time = await connectedDe1().getFlushTimeout();
      var temp = await connectedDe1().getFlushTemperature();
      _rinseStream.add(
        RinseData(
          flow: flow,
          duration: time.toInt(),
          targetTemperature: temp.toInt(),
        ),
      );
    }
  }

  De1Interface connectedDe1() {
    if (_de1 == null) {
      throw const DeviceNotConnectedException.machine();
    }
    return _de1!;
  }

  /// Non-throwing accessor for callers that already model the
  /// "no machine connected" branch (e.g. periodic timers). Returning
  /// `null` here keeps the expected case off the WARNING log path,
  /// which would otherwise reach Crashlytics via the telemetry
  /// forwarder. Use this whenever pre-checking is cheaper than
  /// catching `DeviceNotConnectedException`.
  De1Interface? get connectedDe1OrNull => _de1;

  /// Non-public subject that emits the connection generation when
  /// initialization (machine ready + startup defaults) settles.
  final BehaviorSubject<int?> _initSettledSubject = BehaviorSubject.seeded(
    null,
  );

  /// Fires after machine readiness and startup default writes finish.
  /// WorkflowDeviceSync uses this as the trigger for the on-connect profile
  /// push, replacing the raw de1 stream event which fires before
  /// initialization/defaults complete.
  ///
  /// Emits the connection generation at the time init settled, or null on
  /// disconnect. Consumers compare the value against their own generation
  /// token to reject stale completions from a previous connection.
  Stream<int?> get initSettled => _initSettledSubject.stream;

  /// Current connection generation. Bumped on every disconnect. Used by
  /// WorkflowDeviceSync to sync its generation on connect so that a
  /// subsequent init-settled event matches.
  int get connectionGeneration => _connectionGeneration;

  Future<SteamFormSettings> steamSettings() async {
    if (_de1 == null) {
      throw const DeviceNotConnectedException.machine();
    }
    De1ShotSettings shotSettings = await connectedDe1().shotSettings.first;
    double flowRate = await connectedDe1().getSteamFlow();

    return SteamFormSettings(
      steamEnabled: shotSettings.targetSteamTemp >= 130,
      targetTemp: shotSettings.targetSteamTemp,
      targetDuration: shotSettings.targetSteamDuration,
      targetFlow: flowRate,
    );
  }

  Future<void> updateSteamSettings(SteamFormSettings settings) async {
    De1ShotSettings shotSettings = await connectedDe1().shotSettings.first;
    await connectedDe1().setSteamFlow(settings.targetFlow);
    await connectedDe1().updateShotSettings(
      shotSettings.copyWith(
        targetSteamTemp: settings.steamEnabled ? settings.targetTemp : 0,
        targetSteamDuration: settings.targetDuration,
      ),
    );
    _steamDataController.add(
      SteamSettings(
        targetTemperature: settings.steamEnabled ? settings.targetTemp : 0,
        duration: settings.targetDuration,
        flow: settings.targetFlow,
      ),
    );
  }

  Future<HotWaterFormSettings> hotWaterSettings() async {
    if (_de1 == null) {
      throw const DeviceNotConnectedException.machine();
    }
    De1ShotSettings shotSettings = await connectedDe1().shotSettings.first;
    double flowRate = await connectedDe1().getHotWaterFlow();
    return HotWaterFormSettings(
      targetTemperature: shotSettings.targetHotWaterTemp,
      flow: flowRate,
      volume: shotSettings.targetHotWaterVolume,
      duration: shotSettings.targetHotWaterDuration,
    );
  }

  Future<void> updateHotWaterSettings(HotWaterFormSettings settings) async {
    await connectedDe1().setHotWaterFlow(settings.flow);
    await connectedDe1().shotSettings.first.then((s) async {
      await connectedDe1().updateShotSettings(
        s.copyWith(
          targetHotWaterTemp: settings.targetTemperature,
          targetHotWaterVolume: settings.volume,
          targetHotWaterDuration: settings.duration,
        ),
      );
    });
    _hotWaterDataController.add(
      HotWaterData(
        targetTemperature: settings.targetTemperature,
        duration: settings.duration,
        volume: settings.volume,
        flow: settings.flow,
      ),
    );
  }

  Future<void> updateFlushSettings(RinseData settings) async {
    await connectedDe1().setFlushTimeout(settings.duration.toDouble());
    await connectedDe1().setFlushFlow(settings.flow);
    await connectedDe1().setFlushTemperature(
      settings.targetTemperature.toDouble(),
    );

    _rinseStream.add(settings);
  }

  /// Flow setters live outside the DE1 shot-settings characteristic, so
  /// changing them used to require a nudge re-emit on `shotSettings` to
  /// kick `_shotSettingsUpdate` into rebroadcasting the data-controllers
  /// that UI subscribes to. The nudge leaked redundant WS emits; these
  /// helpers replace it by writing the MMR value and updating the
  /// relevant data-controller directly.
  Future<void> setSteamFlow(double newFlow) async {
    await connectedDe1().setSteamFlow(newFlow);
    final current = _steamDataController.valueOrNull;
    if (current != null) {
      _steamDataController.add(
        SteamSettings(
          targetTemperature: current.targetTemperature,
          duration: current.duration,
          flow: newFlow,
        ),
      );
    }
  }

  Future<void> setHotWaterFlow(double newFlow) async {
    await connectedDe1().setHotWaterFlow(newFlow);
    final current = _hotWaterDataController.valueOrNull;
    if (current != null) {
      _hotWaterDataController.add(
        HotWaterData(
          targetTemperature: current.targetTemperature,
          duration: current.duration,
          volume: current.volume,
          flow: newFlow,
        ),
      );
    }
  }

  Future<void> setFlushFlow(double newFlow) async {
    await connectedDe1().setFlushFlow(newFlow);
    final current = _rinseStream.valueOrNull;
    if (current != null) {
      _rinseStream.add(
        RinseData(
          targetTemperature: current.targetTemperature,
          duration: current.duration,
          flow: newFlow,
        ),
      );
    }
  }

  Future<void> dispose() async {
    // Cancel listeners + pending debounce before tearing down the
    // machine. _onDisconnect() (which normally does this) is not
    // guaranteed to fire: _de1.dispose() closes the transport subjects,
    // which delivers onDone rather than a `disconnected` event.
    _shotSettingsDebounce?.cancel();
    _shotSettingsDebounce = null;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _de1?.dispose();
    _de1 = null;
    if (!_initSettledSubject.isClosed) _initSettledSubject.close();
    if (!_de1Controller.isClosed) _de1Controller.close();
    if (!_steamDataController.isClosed) _steamDataController.close();
    if (!_hotWaterDataController.isClosed) _hotWaterDataController.close();
    if (!_rinseStream.isClosed) _rinseStream.close();
    if (!_shotStateSubject.isClosed) _shotStateSubject.close();
  }
}
