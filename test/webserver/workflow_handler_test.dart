import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/services/webserver/workflow_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../helpers/mock_device_discovery_service.dart';

/// Observes every call the WorkflowHandler + De1Controller make on the
/// DE1 surface. Used to pin the contract down to the device boundary.
///
/// Unlike `helpers/test_de1.dart`, this spy keeps a [BehaviorSubject]
/// for `shotSettings` (mirroring both `MockDe1` and `UnifiedDe1`), so
/// read-modify-write races on the controller surface reproduce here
/// exactly like they do on the running app.
class SpyDe1 implements De1Interface {
  SpyDe1({De1ShotSettings? seed}) {
    _shotSettings = BehaviorSubject.seeded(
      seed ??
          De1ShotSettings(
            steamSetting: 0,
            targetSteamTemp: 150,
            targetSteamDuration: 50,
            targetHotWaterTemp: 75,
            targetHotWaterVolume: 50,
            targetHotWaterDuration: 30,
            targetShotVolume: 36,
            groupTemp: 94.0,
          ),
    );
  }

  late final BehaviorSubject<De1ShotSettings> _shotSettings;

  final List<De1ShotSettings> updateShotSettingsCalls = [];
  final List<Profile> setProfileCalls = [];
  final List<double> setSteamFlowCalls = [];
  final List<double> setHotWaterFlowCalls = [];
  final List<double> setFlushFlowCalls = [];
  final List<double> setFlushTimeoutCalls = [];
  final List<double> setFlushTemperatureCalls = [];

  /// Every emit that crosses the `shotSettings` stream, in order. This
  /// is the stream `/ws/v1/machine/shotSettings` subscribes to.
  final List<De1ShotSettings> emittedShotSettings = [];

  @override
  Stream<De1ShotSettings> get shotSettings =>
      _shotSettings.stream.map((e) {
        emittedShotSettings.add(e);
        return e;
      });

  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) async {
    updateShotSettingsCalls.add(newSettings);
    _shotSettings.add(newSettings);
  }

  @override
  Future<void> setProfile(Profile profile) async {
    setProfileCalls.add(profile);
  }

  @override
  Future<void> setSteamFlow(double newFlow) async {
    setSteamFlowCalls.add(newFlow);
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) async {
    setHotWaterFlowCalls.add(newFlow);
  }

  @override
  Future<void> setFlushFlow(double newFlow) async {
    setFlushFlowCalls.add(newFlow);
  }

  @override
  Future<void> setFlushTimeout(double newTimeout) async {
    setFlushTimeoutCalls.add(newTimeout);
  }

  @override
  Future<void> setFlushTemperature(double newTemp) async {
    setFlushTemperatureCalls.add(newTemp);
  }

  // ---- Uninteresting plumbing ----

  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.connected);
  final BehaviorSubject<MachineSnapshot> _snapshot = BehaviorSubject.seeded(
    MachineSnapshot(
      timestamp: DateTime(2026, 1, 1),
      state: const MachineStateSnapshot(
        state: MachineState.idle,
        substate: MachineSubstate.idle,
      ),
      flow: 0,
      pressure: 0,
      targetFlow: 0,
      targetPressure: 0,
      mixTemperature: 0,
      groupTemperature: 0,
      targetMixTemperature: 0,
      targetGroupTemperature: 0,
      profileFrame: 0,
      steamTemperature: 0,
    ),
  );

  void dispose() {
    _shotSettings.close();
    _connectionState.close();
    _snapshot.close();
  }

  @override
  String get deviceId => 'spy-de1';
  @override
  String get name => 'SpyDe1';
  @override
  DeviceType get type => DeviceType.machine;
  @override
  MachineInfo get machineInfo => MachineInfo(
        version: '1',
        model: '1',
        serialNumber: '1',
        groupHeadControllerPresent: false,
        extra: {},
      );
  @override
  Future<void> onConnect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;
  @override
  Stream<MachineSnapshot> get currentSnapshot => _snapshot.stream;
  @override
  Future<void> requestState(MachineState newState) async {}
  @override
  Stream<bool> get ready => Stream.value(true);
  @override
  Stream<De1WaterLevels> get waterLevels => const Stream.empty();
  @override
  Future<void> setRefillLevel(int newRefillLevel) async {}
  @override
  Future<void> setFanThreshhold(int temp) async {}
  @override
  Future<int> getFanThreshhold() async => 55;
  @override
  Future<int> getTankTempThreshold() async => 0;
  @override
  Future<void> setTankTempThreshold(int temp) async {}
  @override
  Future<double> getSteamFlow() async =>
      setSteamFlowCalls.isEmpty ? 2.1 : setSteamFlowCalls.last;
  @override
  Future<double> getHotWaterFlow() async =>
      setHotWaterFlowCalls.isEmpty ? 10.0 : setHotWaterFlowCalls.last;
  @override
  Future<double> getFlushFlow() async =>
      setFlushFlowCalls.isEmpty ? 6.0 : setFlushFlowCalls.last;
  @override
  Future<double> getFlushTimeout() async =>
      setFlushTimeoutCalls.isEmpty ? 10.0 : setFlushTimeoutCalls.last;
  @override
  Future<double> getFlushTemperature() async =>
      setFlushTemperatureCalls.isEmpty ? 90.0 : setFlushTemperatureCalls.last;
  @override
  Future<double> getFlowEstimation() async => 1.0;
  @override
  Future<void> setFlowEstimation(double multiplier) async {}
  @override
  Future<bool> getUsbChargerMode() async => false;
  @override
  Future<void> setUsbChargerMode(bool t) async {}
  @override
  Future<void> setSteamPurgeMode(int mode) async {}
  @override
  Future<int> getSteamPurgeMode() async => 0;
  @override
  Future<void> enableUserPresenceFeature() async {}
  @override
  Future<void> sendUserPresent() async {}
  @override
  Stream<De1RawMessage> get rawOutStream => const Stream.empty();
  @override
  void sendRawMessage(De1RawMessage message) {}
  @override
  Future<double> getHeaterPhase1Flow() async => 0;
  @override
  Future<void> setHeaterPhase1Flow(double val) async {}
  @override
  Future<double> getHeaterPhase2Flow() async => 0;
  @override
  Future<void> setHeaterPhase2Flow(double val) async {}
  @override
  Future<double> getHeaterPhase2Timeout() async => 0;
  @override
  Future<void> setHeaterPhase2Timeout(double val) async {}
  @override
  Future<double> getHeaterIdleTemp() async => 0;
  @override
  Future<void> setHeaterIdleTemp(double val) async {}
  @override
  Future<void> updateFirmware(Uint8List fwImage,
      {required void Function(double progress) onProgress}) async {}
  @override
  Future<void> cancelFirmwareUpload() async {}
}

Future<void> _settleHandler() async {
  // Workflow handler debounce is 400 ms (private constant). Wait
  // comfortably past that so _applyPendingUpdate fires and the
  // downstream controller writes run to completion.
  await Future<void>.delayed(const Duration(milliseconds: 600));
}

void main() {
  late SpyDe1 spy;
  late DeviceController deviceController;
  late De1Controller de1Controller;
  late WorkflowController workflowController;
  late Handler handler;

  setUp(() async {
    spy = SpyDe1();
    deviceController = DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    de1Controller = De1Controller(controller: deviceController);
    await de1Controller.connectToDe1(spy);
    workflowController = WorkflowController();

    final workflowHandler = WorkflowHandler(
      controller: workflowController,
      de1controller: de1Controller,
    );
    final app = Router().plus;
    workflowHandler.addRoutes(app);
    handler = app.call;
  });

  tearDown(() {
    spy.dispose();
  });

  Future<Response> put(Map<String, dynamic> body) async {
    return await handler(
      Request(
        'PUT',
        Uri.parse('http://localhost/api/v1/workflow'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  group('PUT /api/v1/workflow — redundant writes', () {
    test(
      'steam-only PUT does not trigger hot-water or flush writes',
      () async {
        // Clear any emits from initial seed + DE1 controller init.
        await _settleHandler();
        spy.updateShotSettingsCalls.clear();
        spy.setSteamFlowCalls.clear();
        spy.setHotWaterFlowCalls.clear();
        spy.setFlushFlowCalls.clear();
        spy.setFlushTimeoutCalls.clear();
        spy.setFlushTemperatureCalls.clear();
        spy.setProfileCalls.clear();
        spy.emittedShotSettings.clear();

        unawaited(put({
          'steamSettings': {'duration': 30},
        }));
        await _settleHandler();

        expect(
          spy.setHotWaterFlowCalls,
          isEmpty,
          reason: 'hot-water settings did not change; setHotWaterFlow '
              'must not be invoked',
        );
        expect(
          spy.setFlushFlowCalls,
          isEmpty,
          reason: 'rinse settings did not change; setFlushFlow must not '
              'be invoked',
        );
        expect(
          spy.setFlushTimeoutCalls,
          isEmpty,
          reason: 'rinse settings did not change; setFlushTimeout must '
              'not be invoked',
        );
        expect(
          spy.setFlushTemperatureCalls,
          isEmpty,
          reason: 'rinse settings did not change; setFlushTemperature '
              'must not be invoked',
        );
        expect(
          spy.updateShotSettingsCalls.length,
          equals(1),
          reason: 'exactly one shot-settings write should be issued per '
              'steam-only change',
        );
        expect(
          spy.updateShotSettingsCalls.single.targetSteamDuration,
          equals(30),
        );
      },
    );

    test(
      'no-op PUT (same values) issues no DE1 writes',
      () async {
        await _settleHandler();
        final snapshot = workflowController.currentWorkflow;
        spy.updateShotSettingsCalls.clear();
        spy.setSteamFlowCalls.clear();
        spy.setHotWaterFlowCalls.clear();
        spy.setFlushFlowCalls.clear();
        spy.setFlushTimeoutCalls.clear();
        spy.setFlushTemperatureCalls.clear();
        spy.setProfileCalls.clear();

        unawaited(put({
          'steamSettings': snapshot.steamSettings.toJson(),
          'hotWaterData': snapshot.hotWaterData.toJson(),
          'rinseData': snapshot.rinseData.toJson(),
        }));
        await _settleHandler();

        expect(spy.updateShotSettingsCalls, isEmpty);
        expect(spy.setSteamFlowCalls, isEmpty);
        expect(spy.setHotWaterFlowCalls, isEmpty);
        expect(spy.setFlushFlowCalls, isEmpty);
        expect(spy.setProfileCalls, isEmpty,
            reason: 'identical profile must not be re-sent');
      },
    );
  });

  group('PUT /api/v1/workflow — read-modify-write race', () {
    test(
      'multi-field PUT: final shot-settings write reflects BOTH changes',
      () async {
        await _settleHandler();
        spy.updateShotSettingsCalls.clear();
        spy.emittedShotSettings.clear();

        unawaited(put({
          'steamSettings': {'duration': 44},
          'hotWaterData': {'duration': 55},
        }));
        await _settleHandler();

        expect(
          spy.updateShotSettingsCalls,
          isNotEmpty,
          reason: 'steam + hot-water change must produce at least one '
              'shot-settings write',
        );
        final last = spy.updateShotSettingsCalls.last;
        expect(
          last.targetSteamDuration,
          equals(44),
          reason: 'last updateShotSettings must carry the new steam '
              'duration (lost-write race if stale)',
        );
        expect(
          last.targetHotWaterDuration,
          equals(55),
          reason: 'last updateShotSettings must carry the new hot-water '
              'duration',
        );
      },
    );

    test(
      'WebSocket-observable stream: final emit reflects BOTH changes',
      () async {
        await _settleHandler();
        spy.emittedShotSettings.clear();

        unawaited(put({
          'steamSettings': {'duration': 44},
          'hotWaterData': {'duration': 55},
        }));
        await _settleHandler();

        expect(
          spy.emittedShotSettings,
          isNotEmpty,
          reason: 'handler must produce at least one shotSettings emit',
        );
        final last = spy.emittedShotSettings.last;
        expect(last.targetSteamDuration, equals(44));
        expect(last.targetHotWaterDuration, equals(55));
      },
    );
  });
}
