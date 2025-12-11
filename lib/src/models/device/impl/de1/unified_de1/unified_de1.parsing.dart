part of 'unified_de1.dart';

extension MessageParsing on UnifiedDe1 {
  MachineSnapshot _parseStateAndShotSample(
    ByteData shotSample,
    ByteData stateSample,
  ) {
    final groupPressure = shotSample.getUint16(2) / (1 << 12);
    final groupFlow = shotSample.getUint16(4) / (1 << 12);
    final mixTemp = shotSample.getUint16(6) / (1 << 8);
    final headTemp =
        ((shotSample.getUint8(8) << 16) +
            (shotSample.getUint8(9) << 8) +
            (shotSample.getUint8(10))) /
        (1 << 16);
    final setMixTemp = shotSample.getUint16(11) / (1 << 8);
    final setHeadTemp = shotSample.getUint16(13) / (1 << 8);
    final setGroupPressure = shotSample.getUint8(15) / (1 << 4);
    final setGroupFlow = shotSample.getUint8(16) / (1 << 4);
    final frameNumber = shotSample.getUint8(17);
    final steamTemp = shotSample.getUint8(18);

    var state = De1StateEnum.fromHexValue(stateSample.getInt8(0));
    var subState =
        De1SubState.fromHexValue(stateSample.getInt8(1)) ?? De1SubState.noState;

    return MachineSnapshot(
      timestamp: DateTime.now(),
      state: MachineStateSnapshot(
        state: mapDe1ToMachineState(state),
        substate: mapDe1SubToMachineSubstate(subState),
      ),
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


  _parseWaterLevels(ByteData data) {
    try {
      // notifyFrom(Endpoint.waterLevels, data.buffer.asUint8List());
      var waterlevel = data.getUint16(0, Endian.big);
      var waterThreshold = data.getUint16(2, Endian.big);

      //De1WaterLevelData wlData = De1WaterLevelData(
      //  currentLevel: waterlevel,
      //  currentLimit: waterThreshold,
      //);
      //_waterSubject.add(
      //  De1WaterLevels(
      //    currentPercentage: wlData.getLevelPercent(),
      //    warningThresholdPercentage: 0,
      //  ),
      //);
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

    //_shotSettingsController.add(
    //  De1ShotSettings(
    //    steamSetting: steamBits,
    //    targetSteamTemp: targetSteamTemp,
    //    targetSteamDuration: targetSteamLength,
    //    targetHotWaterTemp: targetWaterTemp,
    //    targetHotWaterVolume: targetWaterVolume,
    //    targetHotWaterDuration: targetWaterLength,
    //    targetShotVolume: targetEspressoVolume,
    //    groupTemp: targetGroupTemp,
    //  ),
    //);
  }
}
