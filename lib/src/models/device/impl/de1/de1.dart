import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.utils.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:logging/logging.dart' as logging;
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';

class De1 with ChangeNotifier implements Machine {
  static String advertisingUUID = '0000FFFF-0000-1000-8000-00805F9B34FB';

  final String _deviceId;

  final _ble = FlutterReactiveBle();

  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  final List<StreamSubscription<dynamic>> _notificationSubscriptions = [];

  final _log = logging.Logger("DE1");

  De1({required String deviceId}) : _deviceId = deviceId {
    _snapshotStream.add(_currentSnapshot);
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    for (StreamSubscription<dynamic> sub in _notificationSubscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  factory De1.fromId(String id) {
    return De1(deviceId: id);
  }

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "DE1";

  @override
  DeviceType get type => DeviceType.machine;

  MachineSnapshot _currentSnapshot = MachineSnapshot(
    flow: 0,
    state: MachineStateSnapshot(
      state: MachineState.booting,
      substate: MachineSubstate.idle,
    ),
    steamTemperature: 0,
    profileFrame: 0,
    targetFlow: 0,
    targetPressure: 0,
    targetMixTemperature: 0,
    targetGroupTemperature: 0,
    timestamp: DateTime.now(),
    groupTemperature: 0,
    mixTemperature: 0,
    pressure: 0,
  );

  final StreamController<MachineSnapshot> _snapshotStream =
      StreamController<MachineSnapshot>.broadcast();

  @override
  Stream<MachineSnapshot> get currentSnapshot => _snapshotStream.stream;

  @override
  Future<void> onConnect() async {
    _snapshotStream.add(_currentSnapshot);

    _connectionSubscription = _ble.connectToDevice(id: _deviceId).listen((
      data,
    ) async {
      _log.info("connection update: ${data}");
      if (data.connectionState == DeviceConnectionState.connected) {
        await _onConnected();
      }
    });
  }

  @override
  Future<void> requestState(MachineState newState) async {
	Uint8List data = Uint8List(1);
	data[0] = De1StateEnum.fromMachineState(newState).hexValue;
    await _write(Endpoint.requestedState, data);
  }

  Future<void> _onConnected() async {
    _log.info("Connected, subscribing to services");
    _snapshotStream.add(
      MachineSnapshot(
        flow: 0,
        state: MachineStateSnapshot(
          state: MachineState.sleeping,
          substate: MachineSubstate.idle,
        ),
        steamTemperature: 0,
        profileFrame: 0,
        targetFlow: 0,
        targetPressure: 0,
        targetMixTemperature: 0,
        targetGroupTemperature: 0,
        timestamp: DateTime.now(),
        groupTemperature: 0,
        mixTemperature: 0,
        pressure: 0,
      ),
    );

    var status = await _read(Endpoint.stateInfo);
    final data = ByteData.sublistView(Uint8List.fromList(status));
    _parseStatus(data);

    _subscribe(Endpoint.stateInfo, _parseStatus);
    _subscribe(Endpoint.shotSample, _parseShot);
  }

  Future<List<int>> _read(Endpoint e) async {
    if (_ble.status != BleStatus.ready) {
      throw ("de1 not connected ${_ble.status}");
    }
    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(de1ServiceUUID),
      characteristicId: Uuid.parse(e.uuid),
      deviceId: deviceId,
    );
    var data = await _ble.readCharacteristic(characteristic);
    return data;
  }

  Future<void> _write(Endpoint e, Uint8List data) async {
    try {
      final characteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(e.uuid),
        serviceId: Uuid.parse(de1ServiceUUID),
        deviceId: deviceId,
      );

      _ble.writeCharacteristicWithoutResponse(characteristic, value: data);
    } catch (e, st) {
      _log.severe("failed to write", e, st);
    }
  }

  void _subscribe(Endpoint e, Function(ByteData) callback) {
    _log.info('enableNotification for ${e.name}');

    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(de1ServiceUUID),
      characteristicId: Uuid.parse(e.uuid),
      deviceId: deviceId,
    );
    var sub = _ble
        .subscribeToCharacteristic(characteristic)
        .listen(
          (data) {
            // Handle connection state updates
            try {
              callback(ByteData.sublistView(Uint8List.fromList(data)));
            } catch (err, stackTrace) {
              _log.severe(
                "failed to invoke callback for ${e.name}",
                err,
                stackTrace,
              );
            }
          },
          onError: (Object error) {
            // Handle a possible error
            _log.severe("Error subscribing to ${e.name}", error);
          },
        );
    _notificationSubscriptions.add(sub);
  }

  _parseStatus(ByteData data) {
    var state = De1StateEnum.fromHexValue(data.getUint8(0));
    var subState =
        De1SubState.fromHexValue(data.getUint8(1)) ?? De1SubState.noState;
    _currentSnapshot = _currentSnapshot.copyWith(
      state: MachineStateSnapshot(
        state: mapDe1ToMachineState(state),
        substate: mapDe1SubToMachineSubstate(subState),
      ),
    );

    _snapshotStream.add(_currentSnapshot);
  }

  _parseShot(ByteData data) {
    //final sampleTime = 100 * (data.getUint16(0)) / (50 * 2);
    final groupPressure = data.getUint16(2) / (1 << 12);
    final groupFlow = data.getUint16(4) / (1 << 12);
    final mixTemp = data.getUint16(6) / (1 << 8);
    final headTemp =
        ((data.getUint8(8) << 16) +
            (data.getUint8(9) << 8) +
            (data.getUint8(10))) /
        (1 << 16);
    final setMixTemp = data.getUint16(11) / (1 << 8);
    final setHeadTemp = data.getUint16(13) / (1 << 8);
    final setGroupPressure = data.getUint8(15) / (1 << 4);
    final setGroupFlow = data.getUint8(16) / (1 << 4);
    final frameNumber = data.getUint8(17);
    final steamTemp = data.getUint8(18);

    _currentSnapshot = _currentSnapshot.copyWith(
      timestamp: DateTime.now(),
      pressure: groupPressure,
      flow: groupFlow,
      mixTemperature: mixTemp,
      groupTemperature: headTemp,
      targetMixTemperature: setMixTemp,
      targetGroupTemperature: setHeadTemp,
      targetPressure: setGroupPressure,
      targetFlow: setGroupFlow,
      profileFrame: frameNumber,
      steamTemperature: steamTemp.toDouble(),
    );
    _snapshotStream.add(_currentSnapshot);
  }
}
