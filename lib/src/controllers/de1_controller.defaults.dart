part of 'de1_controller.dart';

extension Defaults on De1Controller {
  /// Device-pinned default-write helper. Every read/write goes through
  /// the captured [device] so a disconnect/reconnect race cannot write to
  /// the replacement machine.
  Future<void> _setDe1DefaultsFor(De1Interface device) async {
    await device.setFanThreshhold(55);

    if (defaultWorkflow == null) {
      return;
    }
    SteamSettings steamSettings = defaultWorkflow!.steamSettings;
    await _updateSteamSettingsFor(
      device,
      SteamFormSettings(
        steamEnabled: steamSettings.targetTemperature >= 130,
        targetTemp: steamSettings.targetTemperature,
        targetDuration: steamSettings.duration,
        targetFlow: steamSettings.flow,
      ),
    );
    HotWaterData hotWaterData = defaultWorkflow!.hotWaterData;
    await _updateHotWaterSettingsFor(
      device,
      HotWaterFormSettings(
        targetTemperature: hotWaterData.targetTemperature,
        flow: hotWaterData.flow,
        volume: hotWaterData.volume,
        duration: hotWaterData.duration,
      ),
    );

    RinseData rinseData = defaultWorkflow!.rinseData;
    await _updateFlushSettingsFor(device, rinseData);
  }

  Future<void> _updateSteamSettingsFor(
    De1Interface device,
    SteamFormSettings settings,
  ) async {
    De1ShotSettings shotSettings = await device.shotSettings.first;
    await device.setSteamFlow(settings.targetFlow);
    await device.updateShotSettings(
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

  Future<void> _updateHotWaterSettingsFor(
    De1Interface device,
    HotWaterFormSettings settings,
  ) async {
    await device.setHotWaterFlow(settings.flow);
    De1ShotSettings s = await device.shotSettings.first;
    await device.updateShotSettings(
      s.copyWith(
        targetHotWaterTemp: settings.targetTemperature,
        targetHotWaterVolume: settings.volume,
        targetHotWaterDuration: settings.duration,
      ),
    );
    _hotWaterDataController.add(
      HotWaterData(
        targetTemperature: settings.targetTemperature,
        duration: settings.duration,
        volume: settings.volume,
        flow: settings.flow,
      ),
    );
  }

  Future<void> _updateFlushSettingsFor(
    De1Interface device,
    RinseData settings,
  ) async {
    await device.setFlushTimeout(settings.duration.toDouble());
    await device.setFlushFlow(settings.flow);
    await device.setFlushTemperature(
      settings.targetTemperature.toDouble(),
    );
    _rinseStream.add(settings);
  }

  Future<void> applySettingsDefaults() async {
    await _de1?.setFanThreshhold(55);

    await _de1?.setHeaterIdleTemp(95);
    await _de1?.setHeaterPhase1Flow(2.0);
    await _de1?.setHeaterPhase2Flow(4.0);
    await _de1?.setHeaterPhase2Timeout(4.0);

    await _de1?.setRefillKitSettings(.auto);

    await _de1?.setFlowEstimation(1.0);
    await _de1?.setSteamPurgeMode(0);
  }
}
