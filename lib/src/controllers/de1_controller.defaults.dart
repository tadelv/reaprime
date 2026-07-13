part of 'de1_controller.dart';

extension Defaults on De1Controller {
  Future<void> _setDe1Defaults() async {
    await _de1?.setFanThreshhold(55);

    if (defaultWorkflow == null) {
      return;
    }
    SteamSettings steamSettings = defaultWorkflow!.steamSettings;
    await updateSteamSettings(
      SteamFormSettings(
        steamEnabled: steamSettings.targetTemperature >= 130,
        targetTemp: steamSettings.targetTemperature,
        targetDuration: steamSettings.duration,
        targetFlow: steamSettings.flow,
      ),
    );
    HotWaterData hotWaterData = defaultWorkflow!.hotWaterData;
    await updateHotWaterSettings(
      HotWaterFormSettings(
        targetTemperature: hotWaterData.targetTemperature,
        flow: hotWaterData.flow,
        volume: hotWaterData.volume,
        duration: hotWaterData.duration,
      ),
    );

    RinseData rinseData = defaultWorkflow!.rinseData;
    await updateFlushSettings(rinseData);

    // The connect-time profile upload is owned by WorkflowDeviceSync
    // (its `_onDe1Change` connect branch), NOT pushed here: this path is
    // single-shot with swallowed errors, and a mid-sequence failure left
    // the firmware's ProfileDownloadInProgress latch stuck with no retry
    // (magenta GH-LED pulse, start requests ignored).
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
