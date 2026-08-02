import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/firmware_update_state.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
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
  final List<double> steamFlowEntryOrder = [];
  final List<double> steamFlowCompletionOrder = [];

  double? blockedSteamFlow;
  Completer<void>? steamFlowEntered;
  Completer<void>? steamFlowRelease;
  double? failSteamFlow;

  /// Every emit that crosses the `shotSettings` stream, in order. This
  /// is the stream `/ws/v1/machine/shotSettings` subscribes to.
  final List<De1ShotSettings> emittedShotSettings = [];

  @override
  Stream<De1ShotSettings> get shotSettings => _shotSettings.stream.map((e) {
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
    steamFlowEntryOrder.add(newFlow);
    setSteamFlowCalls.add(newFlow);
    if (newFlow == blockedSteamFlow) {
      if (!(steamFlowEntered?.isCompleted ?? true)) {
        steamFlowEntered!.complete();
      }
      await steamFlowRelease!.future;
    }
    if (newFlow == failSteamFlow) {
      failSteamFlow = null;
      throw StateError('selected steam write failed');
    }
    steamFlowCompletionOrder.add(newFlow);
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

  @override
  Future<void> dispose() async {
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
  DeviceImplementation get implementation => DeviceImplementation.unifiedDe1;

  @override
  TransportType get transportType => TransportType.unknown;
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
  double? get cachedFlowEstimation => 1.0;
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
  FirmwareUpdateState get firmwareUpdateState => FirmwareUpdateState.idle;
  @override
  Future<void> updateFirmware(
    Uint8List fwImage, {
    required void Function(double progress) onProgress,
  }) async {}
  @override
  Future<void> cancelFirmwareUpload() async {}
  @override
  Future<De1HeaterVoltage> getHeaterVoltage() async => .v110;
  @override
  Future<De1RefillKitSettings> getRefillKitSettings() async => .auto;
  @override
  Future<void> setHeaterVoltage(De1HeaterVoltage voltage) async {}
  @override
  Future<void> setRefillKitSettings(De1RefillKitSettings settings) async {}
}

Future<void> _settleHandler() async {
  await Future<void>.delayed(Duration.zero);
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

  Future<Response> put(
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    return await handler(
      Request(
        'PUT',
        Uri.parse('http://localhost/api/v1/workflow'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json', ...headers},
      ),
    );
  }

  Future<Response> putRaw(String body) async {
    return await handler(
      Request(
        'PUT',
        Uri.parse('http://localhost/api/v1/workflow'),
        body: body,
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  group('PUT /api/v1/workflow — redundant writes', () {
    test('steam-only PUT does not trigger hot-water or flush writes', () async {
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

      unawaited(
        put({
          'steamSettings': {'duration': 30},
        }),
      );
      await _settleHandler();

      expect(
        spy.setHotWaterFlowCalls,
        isEmpty,
        reason:
            'hot-water settings did not change; setHotWaterFlow '
            'must not be invoked',
      );
      expect(
        spy.setFlushFlowCalls,
        isEmpty,
        reason:
            'rinse settings did not change; setFlushFlow must not '
            'be invoked',
      );
      expect(
        spy.setFlushTimeoutCalls,
        isEmpty,
        reason:
            'rinse settings did not change; setFlushTimeout must '
            'not be invoked',
      );
      expect(
        spy.setFlushTemperatureCalls,
        isEmpty,
        reason:
            'rinse settings did not change; setFlushTemperature '
            'must not be invoked',
      );
      expect(
        spy.updateShotSettingsCalls.length,
        equals(1),
        reason:
            'exactly one shot-settings write should be issued per '
            'steam-only change',
      );
      expect(
        spy.updateShotSettingsCalls.single.targetSteamDuration,
        equals(30),
      );
    });

    test('no-op PUT (same values) issues no DE1 writes', () async {
      await _settleHandler();
      final snapshot = workflowController.currentWorkflow;
      spy.updateShotSettingsCalls.clear();
      spy.setSteamFlowCalls.clear();
      spy.setHotWaterFlowCalls.clear();
      spy.setFlushFlowCalls.clear();
      spy.setFlushTimeoutCalls.clear();
      spy.setFlushTemperatureCalls.clear();
      spy.setProfileCalls.clear();

      unawaited(
        put({
          'steamSettings': snapshot.steamSettings.toJson(),
          'hotWaterData': snapshot.hotWaterData.toJson(),
          'rinseData': snapshot.rinseData.toJson(),
        }),
      );
      await _settleHandler();

      expect(spy.updateShotSettingsCalls, isEmpty);
      expect(spy.setSteamFlowCalls, isEmpty);
      expect(spy.setHotWaterFlowCalls, isEmpty);
      expect(spy.setFlushFlowCalls, isEmpty);
      expect(
        spy.setProfileCalls,
        isEmpty,
        reason: 'identical profile must not be re-sent',
      );
    });
  });

  group('PUT /api/v1/workflow — parse errors (issue #338)', () {
    test('invalid ExitType returns 400 instead of hanging forever', () async {
      await _settleHandler();

      // Send a profile step with an invalid ExitType ('weight'
      // is not a valid member of ExitType {pressure, flow}).
      final future = put({
        'profile': {
          'steps': [
            {
              'name': 'p',
              'pump': 'flow',
              'transition': 'fast',
              'flow': 2,
              'temperature': 93,
              'sensor': 'coffee',
              'seconds': 10,
              'volume': 0,
              'exit': {'type': 'weight', 'condition': 'over', 'value': 36},
            },
          ],
        },
      });

      // Wait for the debounce timer to fire and _applyPendingUpdate
      // to run (or, pre-fix, to throw silently and hang).
      await _settleHandler();

      // With the fix, the completer is completed with a 400 response
      // instead of never completing.
      final response = await future;
      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body, isA<Map<String, dynamic>>());
      expect(body['error'], equals('Invalid request'));
      expect(body['message'], isNotNull);
    });

    test(
      'after a failed parse, a subsequent valid PUT succeeds normally',
      () async {
        await _settleHandler();

        // First: an invalid PUT that will fail to parse.
        final badFuture = put({
          'profile': {
            'steps': [
              {
                'name': 'p',
                'pump': 'flow',
                'transition': 'fast',
                'flow': 2,
                'temperature': 93,
                'sensor': 'coffee',
                'seconds': 10,
                'volume': 0,
                'exit': {'type': 'weight', 'condition': 'over', 'value': 36},
              },
            ],
          },
        });
        await _settleHandler();
        final badResponse = await badFuture;
        expect(badResponse.statusCode, equals(400));

        // Second: a valid PUT that must work because _pendingMerge
        // was cleared after the failure.
        final goodFuture = put({
          'steamSettings': {'duration': 25},
        });
        await _settleHandler();
        final goodResponse = await goodFuture;
        expect(goodResponse.statusCode, equals(200));
        final goodBody = jsonDecode(await goodResponse.readAsString());
        expect(goodBody['steamSettings']['duration'], equals(25));
      },
    );

    test(
      'empty profile title (Profile.fromJson ArgumentError) returns 400',
      () async {
        // Tests the interaction between the new Profile.fromJson
        // validation (throws ArgumentError on empty title) and our
        // catch block in _applyPendingUpdate. Without the catch,
        // this ArgumentError would escape the fire-and-forget Timer
        // callback and hang the request.
        await _settleHandler();

        final future = put({
          'profile': {'title': ''},
        });
        await _settleHandler();

        final response = await future;
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], equals('Invalid request'));
        expect(body['message'], isNotNull);
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

        unawaited(
          put({
            'steamSettings': {'duration': 44},
            'hotWaterData': {'duration': 55},
          }),
        );
        await _settleHandler();

        expect(
          spy.updateShotSettingsCalls,
          isNotEmpty,
          reason:
              'steam + hot-water change must produce at least one '
              'shot-settings write',
        );
        final last = spy.updateShotSettingsCalls.last;
        expect(
          last.targetSteamDuration,
          equals(44),
          reason:
              'last updateShotSettings must carry the new steam '
              'duration (lost-write race if stale)',
        );
        expect(
          last.targetHotWaterDuration,
          equals(55),
          reason:
              'last updateShotSettings must carry the new hot-water '
              'duration',
        );
      },
    );

    test(
      'WebSocket-observable stream: final emit reflects BOTH changes',
      () async {
        await _settleHandler();
        spy.emittedShotSettings.clear();

        unawaited(
          put({
            'steamSettings': {'duration': 44},
            'hotWaterData': {'duration': 55},
          }),
        );
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

  group('PUT /api/v1/workflow — request isolation', () {
    test('rapid PUTs from separate clients are not merged', () async {
      await _settleHandler();
      final initial = workflowController.currentWorkflow;
      final firstName = 'First request';
      final secondDescription = 'Second request';

      final firstFuture = put(
        {'name': firstName},
        headers: {'x-test-client': 'first'},
      );
      final secondFuture = put(
        {'description': secondDescription},
        headers: {'x-test-client': 'second'},
      );

      final responses = await Future.wait([firstFuture, secondFuture]);
      expect(responses[0].statusCode, 200);
      expect(responses[1].statusCode, 200);

      final firstBody = jsonDecode(await responses[0].readAsString());
      final secondBody = jsonDecode(await responses[1].readAsString());
      expect(firstBody['name'], firstName);
      expect(firstBody['description'], initial.description);
      expect(secondBody['name'], firstName);
      expect(secondBody['description'], secondDescription);
      expect(firstBody, isNot(equals(secondBody)));
      expect(workflowController.currentWorkflow.name, firstName);
      expect(workflowController.currentWorkflow.description, secondDescription);
    });

    test(
      'continuous PUT traffic does not wait for an inactivity window',
      () async {
        await _settleHandler();
        final trafficStarted = Completer<void>();
        final laterFutures = <Future<Response>>[];
        final firstFuture = put({'name': 'first'});
        final trafficFuture = () async {
          for (var i = 0; i < 4; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            if (!trafficStarted.isCompleted) {
              trafficStarted.complete();
            }
            laterFutures.add(put({'name': 'later-$i'}));
          }
        }();

        late final Response firstResponse;
        try {
          await trafficStarted.future.timeout(const Duration(seconds: 1));
          firstResponse = await firstFuture.timeout(
            const Duration(milliseconds: 250),
          );
        } finally {
          await trafficFuture;
        }

        expect(firstResponse.statusCode, 200);
        final firstBody = jsonDecode(await firstResponse.readAsString());
        expect(firstBody['name'], 'first');
        final laterResponses = await Future.wait(laterFutures);
        expect(
          laterResponses.every((response) => response.statusCode == 200),
          isTrue,
        );
        expect(workflowController.currentWorkflow.name, 'later-3');
      },
    );

    test(
      'a later workflow PUT cannot overtake an in-flight device apply',
      () async {
        await _settleHandler();
        final initial = workflowController.currentWorkflow;
        final firstFlow = initial.steamSettings.flow + 1;
        final secondFlow = initial.steamSettings.flow + 2;
        final entered = Completer<void>();
        final release = Completer<void>();
        spy.blockedSteamFlow = firstFlow;
        spy.steamFlowEntered = entered;
        spy.steamFlowRelease = release;

        final firstFuture = put({
          'steamSettings': {'flow': firstFlow},
        });
        await entered.future.timeout(const Duration(seconds: 2));
        final secondFuture = put({
          'steamSettings': {'flow': secondFlow},
        });
        var secondCompleted = false;
        unawaited(secondFuture.then((_) => secondCompleted = true));

        try {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect(spy.steamFlowEntryOrder, [firstFlow]);
          expect(secondCompleted, isFalse);
        } finally {
          release.complete();
        }

        final responses = await Future.wait([
          firstFuture.timeout(const Duration(seconds: 2)),
          secondFuture.timeout(const Duration(seconds: 2)),
        ]);
        expect(responses[0].statusCode, 200);
        expect(responses[1].statusCode, 200);
        expect(spy.steamFlowEntryOrder, [firstFlow, secondFlow]);
        expect(spy.steamFlowCompletionOrder, [firstFlow, secondFlow]);
        expect(spy.setSteamFlowCalls.last, secondFlow);
        expect(
          workflowController.currentWorkflow.steamSettings.flow,
          secondFlow,
        );
      },
    );

    test('a failed workflow PUT does not poison later queue entries', () async {
      await _settleHandler();
      final initial = workflowController.currentWorkflow;
      final failedFlow = initial.steamSettings.flow + 1;
      final laterFlow = initial.steamSettings.flow + 2;
      final entered = Completer<void>();
      spy.failSteamFlow = failedFlow;
      spy.blockedSteamFlow = failedFlow;
      spy.steamFlowEntered = entered;
      spy.steamFlowRelease = Completer<void>()..complete();

      final failedFuture = put({
        'steamSettings': {'flow': failedFlow},
      });
      await entered.future.timeout(const Duration(seconds: 2));
      final laterFuture = put({
        'steamSettings': {'flow': laterFlow},
      });

      final responses = await Future.wait([
        failedFuture.timeout(const Duration(seconds: 2)),
        laterFuture.timeout(const Duration(seconds: 2)),
      ]);
      expect(responses[0].statusCode, 500);
      expect(responses[1].statusCode, 200);
      expect(spy.setSteamFlowCalls.last, laterFlow);
      expect(workflowController.currentWorkflow.steamSettings.flow, laterFlow);
    });

    test(
      'an identical retry re-applies a failed workflow device write',
      () async {
        await _settleHandler();
        final initial = workflowController.currentWorkflow;
        final failedFlow = initial.steamSettings.flow + 1;
        spy.failSteamFlow = failedFlow;

        final failedResponse = await put({
          'steamSettings': {'flow': failedFlow},
        });
        expect(failedResponse.statusCode, 500);
        expect(
          workflowController.currentWorkflow.steamSettings.flow,
          initial.steamSettings.flow,
        );

        final retryResponse = await put({
          'steamSettings': {'flow': failedFlow},
        });
        expect(retryResponse.statusCode, 200);
        expect(spy.setSteamFlowCalls, [failedFlow, failedFlow]);
        expect(
          workflowController.currentWorkflow.steamSettings.flow,
          failedFlow,
        );
      },
    );

    test(
      'a concurrent controller mutation survives a blocked REST apply',
      () async {
        await _settleHandler();
        final initial = workflowController.currentWorkflow;
        final nextFlow = initial.steamSettings.flow + 1;
        final entered = Completer<void>();
        final release = Completer<void>();
        spy.blockedSteamFlow = nextFlow;
        spy.steamFlowEntered = entered;
        spy.steamFlowRelease = release;

        final future = put({
          'steamSettings': {'flow': nextFlow},
        });
        await entered.future.timeout(const Duration(seconds: 2));

        workflowController.setWorkflow(
          initial.copyWith(name: 'Concurrent workflow'),
        );
        release.complete();

        final response = await future.timeout(const Duration(seconds: 2));
        expect(response.statusCode, 200);
        expect(workflowController.currentWorkflow.name, 'Concurrent workflow');
        expect(workflowController.currentWorkflow.steamSettings.flow, nextFlow);
        expect(spy.setSteamFlowCalls, [nextFlow, nextFlow]);
      },
    );

    test(
      'request order is reserved before a streamed body completes',
      () async {
        await _settleHandler();
        final body = StreamController<List<int>>();
        final firstFuture = Future<Response>.sync(
          () => handler(
            Request(
              'PUT',
              Uri.parse('http://localhost/api/v1/workflow'),
              body: body.stream,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );
        final secondFuture = put({'name': 'second'});
        var secondCompleted = false;
        unawaited(secondFuture.then((_) => secondCompleted = true));

        await Future<void>.delayed(Duration.zero);
        expect(secondCompleted, isFalse);

        body.add(utf8.encode(jsonEncode({'name': 'first'})));
        await body.close();

        final responses = await Future.wait([firstFuture, secondFuture]);
        expect(responses[0].statusCode, 200);
        expect(responses[1].statusCode, 200);
        final firstBody = jsonDecode(await responses[0].readAsString());
        final secondBody = jsonDecode(await responses[1].readAsString());
        expect(firstBody['name'], 'first');
        expect(secondBody['name'], 'second');
        expect(workflowController.currentWorkflow.name, 'second');
      },
    );

    test(
      'malformed or non-object JSON returns 400 without poisoning the queue',
      () async {
        await _settleHandler();

        final malformedResponse = await putRaw('{');
        expect(malformedResponse.statusCode, 400);

        final badResponse = await putRaw('[]');
        expect(badResponse.statusCode, 400);

        final goodResponse = await put({'name': 'after invalid shape'});
        expect(goodResponse.statusCode, 200);
        expect(workflowController.currentWorkflow.name, 'after invalid shape');
      },
    );
  });
}
