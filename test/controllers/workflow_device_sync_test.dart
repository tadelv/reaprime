import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/controllers/workflow_device_sync.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';

import '../helpers/mock_device_discovery_service.dart';
import '../helpers/test_de1.dart';

Profile _profile(String title) => Profile(
      version: '2',
      title: title,
      notes: '',
      author: 'test',
      beverageType: BeverageType.espresso,
      steps: const [],
      targetVolumeCountStart: 0,
      tankTemperature: 0,
    );

class _RecordingDe1 extends TestDe1 {
  final List<Profile> setProfileCalls = [];

  @override
  Future<void> setProfile(Profile profile) async {
    setProfileCalls.add(profile);
  }
}

void main() {
  late WorkflowController workflow;
  late DeviceController deviceController;
  late De1Controller de1Controller;
  late _RecordingDe1 de1;
  late WorkflowDeviceSync sync;

  setUp(() async {
    workflow = WorkflowController();
    deviceController = DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    de1Controller = De1Controller(controller: deviceController);
    de1 = _RecordingDe1();
    await de1Controller.connectToDe1(de1);
    // Unblock De1Controller._initializeData which awaits shotSettings.first.
    de1.emitShotSettings(De1ShotSettings(
      steamSetting: 0,
      targetSteamTemp: 150,
      targetSteamDuration: 30,
      targetHotWaterTemp: 75,
      targetHotWaterVolume: 50,
      targetHotWaterDuration: 30,
      targetShotVolume: 36,
      groupTemp: 94.0,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    sync = WorkflowDeviceSync(
      workflowController: workflow,
      de1Controller: de1Controller,
    );
  });

  tearDown(() {
    sync.dispose();
    de1.dispose();
  });

  test('profile change triggers exactly one setProfile on the DE1', () async {
    final initial = workflow.currentWorkflow;
    workflow.setWorkflow(initial.copyWith(profile: _profile('Adaptive v2')));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(de1.setProfileCalls.length, equals(1));
    expect(de1.setProfileCalls.single.title, equals('Adaptive v2'));
  });

  test(
    'setWorkflow with identical profile does not push again',
    () async {
      final initial = workflow.currentWorkflow;
      final next = initial.copyWith(profile: _profile('Adaptive v2'));
      workflow.setWorkflow(next);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(de1.setProfileCalls.length, equals(1));

      // Apply a workflow with a semantically-equal profile — should
      // short-circuit via Profile's Equatable equality.
      workflow.setWorkflow(next.copyWith(profile: _profile('Adaptive v2')));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        de1.setProfileCalls.length,
        equals(1),
        reason: 'equal profile value must not trigger a second BLE upload',
      );
    },
  );

  test(
    'non-profile workflow changes do not trigger setProfile',
    () async {
      final initial = workflow.currentWorkflow;
      workflow.setWorkflow(initial.copyWith(name: 'renamed'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(de1.setProfileCalls, isEmpty);
    },
  );

  test(
    'dispose removes the listener — later workflow changes are ignored',
    () async {
      final initial = workflow.currentWorkflow;
      sync.dispose();

      workflow.setWorkflow(initial.copyWith(profile: _profile('After dispose')));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(de1.setProfileCalls, isEmpty);
    },
  );
}
