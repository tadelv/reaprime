import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/remembered_devices_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';

import '../../helpers/mock_settings_service.dart';

void main() {
  late StreamController<RememberedDevice?> machine;
  late StreamController<RememberedDevice?> scale;
  late MockSettingsService settings;
  late RememberedDevicesController controller;

  setUp(() {
    machine = StreamController<RememberedDevice?>.broadcast();
    scale = StreamController<RememberedDevice?>.broadcast();
    settings = MockSettingsService();
  });

  RememberedDevicesController build() => RememberedDevicesController(
        machineConnections: machine.stream,
        scaleConnections: scale.stream,
        settings: settings,
      );

  tearDown(() async {
    await controller.dispose();
    await machine.close();
    await scale.close();
  });

  test('connecting a machine remembers it and persists', () async {
    controller = build();
    await controller.initialize();

    machine.add(const RememberedDevice(
        id: 'de1-1', name: 'DE1', type: DeviceType.machine));
    await Future.delayed(Duration.zero);

    expect(controller.remembered.map((d) => d.id), ['de1-1']);
    expect(RememberedDevice.decodeList(await settings.rememberedDevices())
        .map((d) => d.id), ['de1-1']);
  });

  test('connecting a scale remembers it', () async {
    controller = build();
    await controller.initialize();

    scale.add(const RememberedDevice(
        id: 'wifi:hds.local', name: 'HDS (WiFi)', type: DeviceType.scale));
    await Future.delayed(Duration.zero);

    expect(controller.remembered.single.id, 'wifi:hds.local');
    expect(controller.remembered.single.type, DeviceType.scale);
  });

  test('a null emission (disconnect) does NOT remember/forget', () async {
    controller = build();
    await controller.initialize();

    scale.add(const RememberedDevice(id: 's', name: 'S', type: DeviceType.scale));
    await Future.delayed(Duration.zero);
    scale.add(null); // disconnect
    await Future.delayed(Duration.zero);

    expect(controller.remembered.map((d) => d.id), ['s'],
        reason: 'disconnect keeps it remembered');
  });

  test('registry restores from settings on init', () async {
    await settings.setRememberedDevices(RememberedDevice.encodeList([
      const RememberedDevice(id: 'a', name: 'A', type: DeviceType.scale),
      const RememberedDevice(id: 'b', name: 'B', type: DeviceType.machine),
    ]));
    controller = build();
    await controller.initialize();

    expect(controller.remembered.map((d) => d.id).toSet(), {'a', 'b'});
  });

  test('forget removes and persists', () async {
    await settings.setRememberedDevices(RememberedDevice.encodeList([
      const RememberedDevice(id: 'a', name: 'A', type: DeviceType.scale),
    ]));
    controller = build();
    await controller.initialize();

    await controller.forget('a');
    expect(controller.remembered, isEmpty);
    expect(RememberedDevice.decodeList(await settings.rememberedDevices()),
        isEmpty);
  });

  test('forget is a no-op for an unknown id', () async {
    controller = build();
    await controller.initialize();
    await controller.forget('nope'); // must not throw
    expect(controller.remembered, isEmpty);
  });

  test('re-remembering with a new name updates the entry', () async {
    controller = build();
    await controller.initialize();

    scale.add(const RememberedDevice(id: 's', name: 'Old', type: DeviceType.scale));
    await Future.delayed(Duration.zero);
    scale.add(const RememberedDevice(id: 's', name: 'New', type: DeviceType.scale));
    await Future.delayed(Duration.zero);

    expect(controller.remembered.single.name, 'New');
  });

  test('changes stream emits on remember and forget', () async {
    controller = build();
    await controller.initialize();
    final emissions = <int>[];
    final sub = controller.changes.listen((l) => emissions.add(l.length));

    machine.add(const RememberedDevice(id: 'm', name: 'M', type: DeviceType.machine));
    await Future.delayed(Duration.zero);
    await controller.forget('m');
    await Future.delayed(Duration.zero);

    // seeded [] (0), after remember (1), after forget (0)
    expect(emissions, containsAllInOrder([0, 1, 0]));
    await sub.cancel();
  });
}
