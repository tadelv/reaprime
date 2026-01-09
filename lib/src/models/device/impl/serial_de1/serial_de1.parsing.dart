part of 'serial_de1.dart';

extension SerialDe1Parsing on SerialDe1 {
  _parseShotSample(ByteData data) {
    final groupPressure = data.getUint16(2) / (1 << 12);
    final groupFlow = data.getUint16(4) / (1 << 12);
    final mixTemp = data.getUint16(6) / (1 << 8);
    final headTemp = ((data.getUint8(8) << 16) +
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
      steamTemperature: steamTemp,
    );
  }

  _parseState(ByteData payload) {
    var state = De1StateEnum.fromHexValue(payload.getInt8(0));
    var subState =
        De1SubState.fromHexValue(payload.getInt8(1)) ?? De1SubState.noState;
    _currentSnapshot = _currentSnapshot.copyWith(
      state: MachineStateSnapshot(
        state: mapDe1ToMachineState(state),
        substate: mapDe1SubToMachineSubstate(subState),
      ),
    );
  }

  _parseWaterLevels(ByteData data) {
    try {
      // notifyFrom(Endpoint.waterLevels, data.buffer.asUint8List());
      var waterlevel = data.getUint16(0, Endian.big);
      var waterThreshold = data.getUint16(2, Endian.big);

      De1WaterLevelData wlData = De1WaterLevelData(
        currentLevel: waterlevel,
        currentLimit: waterThreshold,
      );
      _waterSubject.add(
        De1WaterLevels(
          currentLevel: wlData.getLevelPercent(),
          refillLevel: 0,
        ),
      );
    } catch (e) {
      _log.severe("waternotify", e);
    }
  }


  _parseShotSettings(ByteData data) {
    var steamBits = data.getUint8(0);
    var targetSteamTemp = data.getUint8(1);
    var targetSteamLength = data.getUint8(2);
    var targetWaterTemp = data.getUint8(3);
    var targetWaterVolume = data.getUint8(4);
    var targetWaterLength = data.getUint8(5);
    var targetEspressoVolume = data.getUint8(6);
    var targetGroupTemp = data.getUint16(7) / (1 << 8);

    _log.info('SteamBits = ${steamBits.toRadixString(16)}');
    _log.info('TargetSteamTemp = $targetSteamTemp');
    _log.info('TargetSteamLength = $targetSteamLength');
    _log.info('TargetWaterTemp = $targetWaterTemp');
    _log.info('TargetWaterVolume = $targetWaterVolume');
    _log.info('TargetWaterLength = $targetWaterLength');
    _log.info('TargetEspressoVolume = $targetEspressoVolume');
    _log.info('TargetGroupTemp = $targetGroupTemp');

    _shotSettingsController.add(
      De1ShotSettings(
        steamSetting: steamBits,
        targetSteamTemp: targetSteamTemp,
        targetSteamDuration: targetSteamLength,
        targetHotWaterTemp: targetWaterTemp,
        targetHotWaterVolume: targetWaterVolume,
        targetHotWaterDuration: targetWaterLength,
        targetShotVolume: targetEspressoVolume,
        groupTemp: targetGroupTemp,
      ),
    );
  }
}
