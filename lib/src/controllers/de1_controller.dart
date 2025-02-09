import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/forms/hot_water_form.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:rxdart/subjects.dart';

class De1Controller {
  final DeviceController _deviceController;

  De1Interface? _de1;
  final Logger _log = Logger("De1Controller");

  final BehaviorSubject<De1Interface?> _de1Controller =
      BehaviorSubject.seeded(null);

  Stream<De1Interface?> get de1 => _de1Controller.stream;

  final BehaviorSubject<De1ControllerSteamSettings> _steamDataController =
      BehaviorSubject.seeded(De1ControllerSteamSettings(
    targetTemperature: 0,
    flow: 0,
    duration: 0,
  ));

  Stream<De1ControllerSteamSettings> get steamData =>
      _steamDataController.stream;

  final BehaviorSubject<De1ControllerHotWaterData> _hotWaterDataController =
      BehaviorSubject.seeded(De1ControllerHotWaterData(
    targetTemperature: 0,
    flow: 0,
    duration: 0,
    volume: 0,
  ));

  Stream<De1ControllerHotWaterData> get hotWaterData =>
      _hotWaterDataController.stream;

  final BehaviorSubject<De1ControllerRinseData> _rinseStream =
      BehaviorSubject.seeded(De1ControllerRinseData(
          duration: 5, targetTemperature: 90, flow: 2.5));

  Stream<De1ControllerRinseData> get rinseData => _rinseStream.stream;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  De1Controller({required DeviceController controller})
      : _deviceController = controller {
    _log.info("checking ${_deviceController.devices}");
    _deviceController.deviceStream.listen((devices) async {
      var de1List = devices.whereType<De1Interface>().toList();
      if (de1List.firstOrNull != null && _de1 == null) {
        var de1 = de1List.first;
        _log.fine("found de1, connecting");
        await de1.onConnect();
        _de1 = de1;
        _de1Controller.add(_de1);

        _de1!.ready.listen((ready) {
          if (ready) {
            _initializeData();
          }
        });
      }
    });
  }

  _initializeData() async {
    connectedDe1().shotSettings.first.then(_shotSettingsUpdate);
    _subscriptions.add(
      connectedDe1().shotSettings.listen(
            _shotSettingsUpdate,
          ),
    );
  }

  _shotSettingsUpdate(De1ShotSettings data) async {
    _log.info('received shot settings');
    var steamFlow = await connectedDe1().getSteamFlow();
    _steamDataController.add(
      De1ControllerSteamSettings(
        duration: data.targetSteamDuration,
        targetTemperature: data.targetSteamTemp,
        flow: steamFlow,
      ),
    );
    var hwFlow = await connectedDe1().getHotWaterFlow();
    _hotWaterDataController.add(
      De1ControllerHotWaterData(
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
      _rinseStream.add(De1ControllerRinseData(
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

  Future<void> updateFlushSettings(De1ControllerRinseData settings) async {
    await connectedDe1().setFlushTimeout(settings.duration.toDouble());
    await connectedDe1().setFlushFlow(settings.flow);
    await connectedDe1()
        .setFlushTemperature(settings.targetTemperature.toDouble());

    _rinseStream.add(settings);
  }
}

class De1ControllerSteamSettings {
  int targetTemperature;
  int duration;
  double flow;

  De1ControllerSteamSettings({
    required this.targetTemperature,
    required this.duration,
    required this.flow,
  });

  De1ControllerSteamSettings copyWith({
    int? targetTemperature,
    int? duration,
    double? flow,
  }) {
    return De1ControllerSteamSettings(
        targetTemperature: targetTemperature ?? this.targetTemperature,
        duration: duration ?? this.duration,
        flow: flow ?? this.flow);
  }
}

class De1ControllerHotWaterData {
  int targetTemperature;
  int duration;
  int volume;
  double flow;

  De1ControllerHotWaterData(
      {required this.targetTemperature,
      required this.duration,
      required this.volume,
      required this.flow});

  De1ControllerHotWaterData copyWith({
    int? targetTemperature,
    int? duration,
    int? volume,
    double? flow,
  }) {
    return De1ControllerHotWaterData(
      targetTemperature: targetTemperature ?? this.targetTemperature,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      flow: flow ?? this.flow,
    );
  }
}

class De1ControllerRinseData {
  int targetTemperature;
  int duration;
  double flow;

  De1ControllerRinseData({
    required this.targetTemperature,
    required this.duration,
    required this.flow,
  });
}
