import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/forms/hot_water_form.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:rxdart/subjects.dart';

part 'de1_controller.defaults.dart';

class De1Controller {
  final DeviceController _deviceController;

  Workflow? defaultWorkflow;

  De1Interface? _de1;
  final Logger _log = Logger("De1Controller");

  final BehaviorSubject<De1Interface?> _de1Controller =
      BehaviorSubject.seeded(null);

  Stream<De1Interface?> get de1 => _de1Controller.stream;

  final BehaviorSubject<SteamSettings> _steamDataController =
      BehaviorSubject.seeded(SteamSettings(
    targetTemperature: 0,
    flow: 0,
    duration: 0,
  ));

  Stream<SteamSettings> get steamData =>
      _steamDataController.stream;

  final BehaviorSubject<HotWaterData> _hotWaterDataController =
      BehaviorSubject.seeded(HotWaterData(
    targetTemperature: 0,
    flow: 0,
    duration: 0,
    volume: 0,
  ));

  Stream<HotWaterData> get hotWaterData =>
      _hotWaterDataController.stream;

  final BehaviorSubject<RinseData> _rinseStream =
      BehaviorSubject.seeded(
    RinseData(
      duration: 5,
      targetTemperature: 90,
      flow: 2.5,
    ),
  );

  Stream<RinseData> get rinseData => _rinseStream.stream;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _dataInitialized = false;
  Timer? _shotSettingsDebounce;

  De1Controller({required DeviceController controller})
      : _deviceController = controller {
    _log.info("checking ${_deviceController.devices}");
  }

  Future<void> connectToDe1(De1Interface de1Interface) async {
    if (de1Interface == _de1) {
        _log.fine("trying to connect to existing de1, exit early");
        return;
      }
    _onDisconnect(); // just in case
    _de1 = de1Interface;
    _log.fine("found de1, connecting");
    await de1Interface.onConnect();
    _de1Controller.add(_de1);

    _subscriptions.add(
      _de1!.ready.listen(
        (ready) {
          if (ready) {
            _initializeData();
          }
        },
      ),
    );

    _subscriptions.add(
      _de1!.connectionState.listen(
        (connectionData) {
          switch (connectionData) {
            case ConnectionState.connecting:
              _log.info("device $_de1 connecting");
            case ConnectionState.connected:
              _log.info("device $_de1 connected");
            case ConnectionState.disconnecting:
              _log.info("device $_de1 disconnecting");
            case ConnectionState.disconnected:
              _log.info("device $_de1 disconnected, resetting");
              _onDisconnect();
          }
        },
      ),
    );
  }

  void _onDisconnect() {
    _log.info("resetting de1");
    _de1 = null;
    _de1Controller.add(_de1);
    _dataInitialized = false;
    _shotSettingsDebounce?.cancel();
    _shotSettingsDebounce = null;
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> _initializeData() async {
    if (_dataInitialized) {
      _log.warning("Data already initialized, skipping (this should only happen once!)");
      return;
    }
    _log.info("Initializing DE1 data for the first time");
    _dataInitialized = true;
    
    await connectedDe1().shotSettings.first.then(_shotSettingsUpdate);
    _subscriptions.add(
      connectedDe1().shotSettings.listen(
            _shotSettingsUpdate,
          ),
    );
    _log.info("Created shotSettings listener, total subscriptions: ${_subscriptions.length}");
    await _setDe1Defaults();
  }

  Future<void> _shotSettingsUpdate(De1ShotSettings data) async {
    // Debounce rapid successive calls (e.g., from setSteamFlow + setHotWaterFlow + updateShotSettings)
    _shotSettingsDebounce?.cancel();
    _shotSettingsDebounce = Timer(const Duration(milliseconds: 100), () async {
      _log.info('Processing shot settings update (debounced)');
      await _processShotSettingsUpdate(data);
    });
  }

  Future<void> _processShotSettingsUpdate(De1ShotSettings data) async {
    var steamFlow = await connectedDe1().getSteamFlow();
    _steamDataController.add(
      SteamSettings(
        duration: data.targetSteamDuration,
        targetTemperature: data.targetSteamTemp,
        flow: steamFlow,
      ),
    );
    var hwFlow = await connectedDe1().getHotWaterFlow();
    _hotWaterDataController.add(
      HotWaterData(
        volume: data.targetHotWaterVolume,
        flow: hwFlow,
        targetTemperature: data.targetHotWaterTemp,
        duration: data.targetHotWaterDuration,
      ),
    );
    {
      var flow = await connectedDe1().getFlushFlow();
      var time = await connectedDe1().getFlushTimeout();
      var temp = await connectedDe1().getFlushTemperature();
      _rinseStream.add(RinseData(
        flow: flow,
        duration: time.toInt(),
        targetTemperature: temp.toInt(),
      ));
    }
  }

  De1Interface connectedDe1() {
    if (_de1 == null) {
      throw "De1 not connected yet";
    }
    return _de1!;
  }

  Future<SteamFormSettings> steamSettings() async {
    if (_de1 == null) {
      throw "De1 not connected yet";
    }
    De1ShotSettings shotSettings = await connectedDe1().shotSettings.first;
    double flowRate = await connectedDe1().getSteamFlow();

    return SteamFormSettings(
      steamEnabled: shotSettings.targetSteamTemp >= 130,
      targetTemp: shotSettings.targetSteamTemp,
      targetDuration: shotSettings.targetSteamDuration,
      targetFlow: flowRate,
    );
  }

  Future<void> updateSteamSettings(SteamFormSettings settings) async {
    De1ShotSettings shotSettings = await connectedDe1().shotSettings.first;
    await connectedDe1().setSteamFlow(settings.targetFlow);
    await connectedDe1().updateShotSettings(shotSettings.copyWith(
      targetSteamTemp: settings.steamEnabled ? settings.targetTemp : 0,
      targetSteamDuration: settings.targetDuration,
    ));
    _steamDataController.first.then((d) {
      _steamDataController.add(d.copyWith(flow: settings.targetFlow));
    });
  }

  Future<HotWaterFormSettings> hotWaterSettings() async {
    if (_de1 == null) {
      throw "De1 not connected yet";
    }
    De1ShotSettings shotSettings = await connectedDe1().shotSettings.first;
    double flowRate = await connectedDe1().getHotWaterFlow();
    return HotWaterFormSettings(
      targetTemperature: shotSettings.targetHotWaterTemp,
      flow: flowRate,
      volume: shotSettings.targetHotWaterVolume,
      duration: shotSettings.targetHotWaterDuration,
    );
  }

  Future<void> updateHotWaterSettings(HotWaterFormSettings settings) async {
    await connectedDe1().setHotWaterFlow(settings.flow);
    await connectedDe1().shotSettings.first.then((s) async {
      await connectedDe1().updateShotSettings(s.copyWith(
          targetHotWaterTemp: settings.targetTemperature,
          targetHotWaterVolume: settings.volume,
          targetHotWaterDuration: settings.duration));
    });
    _hotWaterDataController.first.then((d) {
      _hotWaterDataController.add(d.copyWith(flow: settings.flow));
    });
  }

  Future<void> updateFlushSettings(RinseData settings) async {
    await connectedDe1().setFlushTimeout(settings.duration.toDouble());
    await connectedDe1().setFlushFlow(settings.flow);
    await connectedDe1()
        .setFlushTemperature(settings.targetTemperature.toDouble());

    _rinseStream.add(settings);
  }
}

