part of 'de1_controller.dart';

extension Defaults on De1Controller {
  Future<void> _setDe1Defaults() async {
    await _de1?.setFanThreshhold(55);

    // TODO: set heater defaults

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


    final defaultProfile = defaultWorkflow?.profile;
    if (defaultProfile == null) {
      return;
    }
    await _de1?.setProfile(defaultProfile);
  }
}
