import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_firmwaremodel.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.utils.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:rxdart/transformers.dart';

part 'unified_de1.mmr.dart';
part 'unified_de1.parsing.dart';
part 'unified_de1.profile.dart';
part 'unified_de1.firmware.dart';
part 'unified_de1.raw.dart';

// Add this configuration class
class _MMRConfig {
  final MMRItem item;
  final double readScale;
  final double writeScale;
  final int? minValue;
  final int? maxValue;

  const _MMRConfig({
    required this.item,
    this.readScale = 1.0,
    this.writeScale = 1.0,
    this.minValue,
    this.maxValue,
  });
}

class UnifiedDe1 implements De1Interface {
  static String advertisingUUID = 'ffff';
  final UnifiedDe1Transport _transport;

  final Logger _log = Logger("DE1");

  Stream<ByteData>? _cachedMmrStream;

  UnifiedDe1({required DataTransport transport})
    : _transport = UnifiedDe1Transport(transport: transport);

  @override
  Stream<ConnectionState> get connectionState => _transport.connectionState.map(
    (e) => e ? ConnectionState.connected : ConnectionState.disconnected,
  );

  @override
  Stream<MachineSnapshot> get currentSnapshot =>
      _transport.shotSample
          .map((d) {
            notifyFrom(Endpoint.shotSample, d.buffer.asUint8List());
            return d;
          })
          .withLatestFrom(
            _transport.state.map((d) {
              notifyFrom(Endpoint.stateInfo, d.buffer.asUint8List());
              return d;
            }),
            (snp, st) {
              final snapshot = _parseStateAndShotSample(st, snp);
              _log.finest("new state: ${snapshot.toJson()}");
              return snapshot;
            },
          )
          .asBroadcastStream();

  @override
  String get deviceId => _transport.id;

  MachineInfo? _info;
  @override
  MachineInfo get machineInfo =>
      _info ??
      MachineInfo(
        version: "0",
        model: "Unknown",
        serialNumber: "0",
        groupHeadControllerPresent: false,
        extra: {},
      );

  @override
  Future<void> disconnect() async {
    await _transport.disconnect();
  }

  @override
  Future<int> getFanThreshhold() async {
    return await _readMMRInt(MMRItem.fanThreshold);
  }

  @override
  Future<double> getFlushFlow() async {
    return await _readMMRScaled(MMRItem.flushFlowRate);
  }

  @override
  Future<double> getFlushTemperature() async {
    return await _readMMRScaled(MMRItem.flushTemp);
  }

  @override
  Future<double> getFlushTimeout() async {
    return await _readMMRScaled(MMRItem.flushTimeout);
  }

  @override
  Future<double> getHeaterIdleTemp() async {
    return await _readMMRScaled(MMRItem.waterHeaterIdleTemp);
  }

  @override
  Future<double> getHeaterPhase1Flow() async {
    return await _readMMRScaled(MMRItem.heaterUp1Flow);
  }

  @override
  Future<double> getHeaterPhase2Flow() async {
    return await _readMMRScaled(MMRItem.heaterUp2Flow);
  }

  @override
  Future<double> getHeaterPhase2Timeout() async {
    return await _readMMRScaled(MMRItem.heaterUp2Timeout);
  }

  @override
  Future<double> getHotWaterFlow() async {
    return await _readMMRScaled(MMRItem.hotWaterFlowRate);
  }

  @override
  Future<double> getSteamFlow() async {
    return await _readMMRScaled(MMRItem.targetSteamFlow);
  }

  @override
  Future<int> getTankTempThreshold() async {
    return await _readMMRInt(MMRItem.tankTemp);
  }

  @override
  Future<bool> getUsbChargerMode() async {
    final result = await _readMMRInt(MMRItem.allowUSBCharging);
    return result == 1;
  }

  @override
  Future<int> getSteamPurgeMode() async {
    return await _readMMRInt(MMRItem.steamPurgeMode);
  }

  @override
  String get name => "DE1";

  @override
  Future<void> onConnect() async {
    initRawStream();
    await _transport.connect();

    if (_info != null) {
      return;
    }

    final model = _unpackMMRInt(await _mmrRead(MMRItem.v13Model));
    final ghcInfo = _unpackMMRInt(await _mmrRead(MMRItem.ghcInfo));
    final serial = _unpackMMRInt(await _mmrRead(MMRItem.serialN));
    final firmware = _unpackMMRInt(await _mmrRead(MMRItem.cpuFirmwareBuild));
    final voltage = _unpackMMRInt(await _mmrRead(MMRItem.heaterV));
    final refillKit = _unpackMMRInt(await _mmrRead(MMRItem.refillKitPresent));

    _info = MachineInfo(
      version: "$firmware",
      model: DecentMachineModel.fromInt(model).name,
      serialNumber: "$serial",
      groupHeadControllerPresent: (ghcInfo & 0x04) > 1,
      extra: {'refillKit': (refillKit & 0x01) != 0, 'voltage': voltage},
    );

    _log.info("Info: ${_info!.toJson()}");

    // TODO: User configurable setting
    // Set refill kit to autodetect
    await _mmrWrite(MMRItem.refillKitPresent, [0x02]);
  }

  final StreamController<De1RawMessage> _rawMessageController =
      StreamController.broadcast();

  @override
  Stream<De1RawMessage> get rawOutStream => _rawMessageController.stream;

  @override
  Stream<bool> get ready => _transport.connectionState.asBroadcastStream();

  @override
  Future<void> requestState(MachineState newState) async {
    Uint8List data = Uint8List(1);
    data[0] = De1StateEnum.fromMachineState(newState).hexValue;
    await _transport.writeWithResponse(Endpoint.requestedState, data);
  }

  final StreamController<De1RawMessage> _rawInputController =
      StreamController();
  @override
  void sendRawMessage(De1RawMessage message) {
    _rawInputController.add(message);
  }

  @override
  Future<void> setFanThreshhold(int temp) async {
    await _writeMMRInt(MMRItem.fanThreshold, temp);
  }

  @override
  Future<void> setFlushFlow(double newFlow) async {
    await _writeMMRScaled(MMRItem.flushFlowRate, newFlow);
  }

  @override
  Future<void> setFlushTemperature(double newTemp) async {
    await _writeMMRScaled(MMRItem.flushTemp, newTemp);
  }

  @override
  Future<void> setFlushTimeout(double newTimeout) async {
    await _writeMMRScaled(MMRItem.flushTimeout, newTimeout);
  }

  @override
  Future<void> setHeaterIdleTemp(double val) async {
    await _writeMMRScaled(MMRItem.waterHeaterIdleTemp, val);
  }

  @override
  Future<void> setHeaterPhase1Flow(double val) async {
    await _writeMMRScaled(MMRItem.heaterUp1Flow, val);
  }

  @override
  Future<void> setHeaterPhase2Flow(double val) async {
    await _writeMMRScaled(MMRItem.heaterUp2Flow, val);
  }

  @override
  Future<void> setHeaterPhase2Timeout(double val) async {
    await _writeMMRScaled(MMRItem.heaterUp2Timeout, val);
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) async {
    await _writeMMRScaled(MMRItem.hotWaterFlowRate, newFlow);
    // Workaround for hot water flow not part of shot settings, will trigger
    // DE1Controller refresh
    _transport.shotSettingsSubject.add(
      await _transport.shotSettingsSubject.first,
    );
  }

  @override
  Future<void> setProfile(Profile profile) async {
    await _sendProfile(profile);
  }

  @override
  Future<void> setSteamFlow(double newFlow) async {
    await _writeMMRScaled(MMRItem.targetSteamFlow, newFlow);
    // Workaround for steam flow not part of shot settings, will trigger
    // DE1Controller refresh
    _transport.shotSettingsSubject.add(
      await _transport.shotSettingsSubject.first,
    );
  }

  @override
  Future<void> setTankTempThreshold(int temp) async {
    await _writeMMRInt(MMRItem.tankTemp, temp);
  }

  @override
  Future<void> setUsbChargerMode(bool t) async {
    await _writeMMRInt(MMRItem.allowUSBCharging, t ? 1 : 0);
  }

  @override
  Future<void> setSteamPurgeMode(int mode) async {
    await _writeMMRInt(MMRItem.steamPurgeMode, mode);
  }

  @override
  Future<void> setRefillLevel(int newThresholdPercentage) async {
    ByteData value = ByteData(4);
    try {
      // 00 00 0c 00
      // 00 00 00 07
      // TODO; check percentaeg
      value.setInt16(0, 0, Endian.big);
      value.setInt16(2, newThresholdPercentage * 256, Endian.big);
      _transport.writeWithResponse(
        Endpoint.waterLevels,
        value.buffer.asUint8List(),
      );
    } catch (e) {
      _log.severe("failed to set water warning", e);
      rethrow;
    }
  }

  @override
  Stream<De1ShotSettings> get shotSettings => _transport.shotSettings
      .map((d) {
        notifyFrom(Endpoint.shotSettings, d.buffer.asUint8List());
        return d;
      })
      .map(_parseShotSettings);

  @override
  DeviceType get type => DeviceType.machine;

  @override
  Future<void> updateFirmware(
    Uint8List fwImage, {
    required void Function(double progress) onProgress,
  }) async {
    await _updateFirmware(fwImage, onProgress);
  }

  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) async {
    Uint8List data = Uint8List(9);

    int index = 0;
    data[index] = newSettings.steamSetting;
    index++;
    data[index] = newSettings.targetSteamTemp;
    index++;
    data[index] = newSettings.targetSteamDuration;
    index++;
    data[index] = newSettings.targetHotWaterTemp;
    index++;
    data[index] = newSettings.targetHotWaterVolume;
    index++;
    data[index] = newSettings.targetHotWaterDuration;
    index++;
    data[index] = newSettings.targetShotVolume;
    index++;

    data[index] = newSettings.groupTemp.toInt();
    index++;
    data[index] =
        ((newSettings.groupTemp - newSettings.groupTemp.floor()) * 256.0)
            .toInt();
    index++;

    await _transport.writeWithResponse(Endpoint.shotSettings, data);
    _transport.shotSettingsSubject.add(ByteData.sublistView(data));
  }

  @override
  Stream<De1WaterLevels> get waterLevels => _transport.waterLevels
      .map((d) {
        notifyFrom(Endpoint.waterLevels, d.buffer.asUint8List());
        return d;
      })
      .map(_parseWaterLevels);

  // Private getter for MMR stream with notifyFrom called once per event
  // Cached to ensure only one stream chain is created
  Stream<ByteData> get _mmr {
    _cachedMmrStream ??= _transport.mmr.map((d) {
      notifyFrom(Endpoint.readFromMMR, d.buffer.asUint8List());
      return d;
    }).asBroadcastStream();
    return _cachedMmrStream!;
  }
}


