part of 'de1.dart';

extension De1Subscriptions on De1 {
  Future<void> _subscribe(Endpoint e, Function(ByteData) callback) async {
    _log.info('enableNotification for ${e.name}');

    final characteristic = _service.characteristics
        .firstWhere((c) => c.uuid == e.uuid);

    final sub = characteristic.onValueReceived.listen((data) {
      try {
        callback(ByteData.sublistView(Uint8List.fromList(data)));
      } catch (err, stackTrace) {
        _log.severe(
          "failed to invoke callback for ${e.name}",
          err,
          stackTrace,
        );
      }
    });
    _subscriptions.add(sub);

    await characteristic.notifications.subscribe();
  }

  _parseStatus(ByteData data) {
    notifyFrom(Endpoint.stateInfo, data.buffer.asUint8List());
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
    notifyFrom(Endpoint.shotSample, data.buffer.asUint8List());
    //final sampleTime = 100 * (data.getUint16(0)) / (50 * 2);
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
    _snapshotStream.add(_currentSnapshot);
  }

  _parseShotSettings(ByteData data) {
    notifyFrom(Endpoint.shotSettings, data.buffer.asUint8List());
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

  _parseWaterLevels(ByteData data) {
    try {
      notifyFrom(Endpoint.waterLevels, data.buffer.asUint8List());
      var waterlevel = data.getUint16(0, Endian.big);
      var waterThreshold = data.getUint16(2, Endian.big);

      De1WaterLevelData wlData = De1WaterLevelData(
        currentLevel: waterlevel,
        currentLimit: waterThreshold,
      );
      _waterLevelsController.add(
        De1WaterLevels(
          currentPercentage: wlData.getLevelPercent(),
          warningThresholdPercentage: 0,
        ),
      );
    } catch (e) {
      _log.severe("waternotify", e);
    }
  }

  void _parseVersion(ByteData value) {
    var bleAPIVersion = value.getUint8(0);
    var bleRelease = value.getUint8(1);
    var bleCommits = value.getUint16(2);
    var bleChanges = value.getUint8(4);
    var bleSHA = value.getUint32(5);

    var fwAPIVersion = value.getUint8(9);
    var fwRelease = value.getUint8(10);
    var fwCommits = value.getUint16(11);
    var fwChanges = value.getUint8(13);
    var fwSHA = value.getUint32(14);

    _log.info('bleAPIVersion = ${bleAPIVersion.toRadixString(16)}');
    _log.info('bleRelease = ${bleRelease.toRadixString(16)}');
    _log.info('bleCommits = ${bleCommits.toRadixString(16)}');
    _log.info('bleChanges = ${bleChanges.toRadixString(16)}');
    _log.info('bleSHA = ${bleSHA.toRadixString(16)}');
    _log.info('fwAPIVersion = ${fwAPIVersion.toRadixString(16)}');
    _log.info('fwRelease = ${fwRelease.toRadixString(16)}');
    _log.info('fwCommits = ${fwCommits.toRadixString(16)}');
    _log.info('fwChanges = ${fwChanges.toRadixString(16)}');
    _log.info('fwSHA = ${fwSHA.toRadixString(16)}');
  }
}

final class De1WaterLevelData {
  final int currentLevel;
  final int currentLimit;

  const De1WaterLevelData({
    required this.currentLevel,
    required this.currentLimit,
  });

  int getLevelPercent() {
    var l = currentLevel - currentLimit;
    return l * 100 ~/ 8300;
  }
}
