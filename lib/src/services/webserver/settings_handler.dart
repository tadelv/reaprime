part of '../webserver_service.dart';

class SettingsHandler {
  final SettingsController _controller;
  final WebUIService _webUIService;
  final WebUIStorage _webUIStorage;
  final BatteryController? _batteryController;

  SettingsHandler({
    required SettingsController controller,
    required WebUIService service,
    required WebUIStorage webUIStorage,
    BatteryController? batteryController,
  }) : _controller = controller,
       _webUIService = service,
       _webUIStorage = webUIStorage,
       _batteryController = batteryController;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/settings', () async {
      log.info("handling settings");
      final gatewayMode = _controller.gatewayMode.name;
      final webPath = _webUIService.serverPath();
      final logLevel = _controller.logLevel;
      final weightFlowMultiplier = _controller.weightFlowMultiplier;
      final volumeFlowMultiplier = _controller.volumeFlowMultiplier;
      final scalePowerMode = _controller.scalePowerMode.name;
      final preferredMachineId = _controller.preferredMachineId;
      final preferredScaleId = _controller.preferredScaleId;
      final defaultSkinId = _controller.defaultSkinId;
      final automaticUpdateCheck = _controller.automaticUpdateCheck;
      final result = <String, dynamic>{
        'gatewayMode': gatewayMode,
        'webUiPath': webPath,
        'logLevel': logLevel,
        'weightFlowMultiplier': weightFlowMultiplier,
        'volumeFlowMultiplier': volumeFlowMultiplier,
        'scalePowerMode': scalePowerMode,
        'preferredMachineId': preferredMachineId,
        'preferredScaleId': preferredScaleId,
        'defaultSkinId': defaultSkinId,
        'automaticUpdateCheck': automaticUpdateCheck,
        'chargingMode': _controller.chargingMode.name,
        'nightModeEnabled': _controller.nightModeEnabled,
        'nightModeSleepTime': _controller.nightModeSleepTime,
        'nightModeMorningTime': _controller.nightModeMorningTime,
      };
      if (_batteryController?.currentChargingState != null) {
        result['chargingState'] = _batteryController!.currentChargingState!.toJson();
      }
      return result;
    });
    app.post('/api/v1/settings', (Request request) async {
      final payload = await request.readAsString();
      Map<String, dynamic> json = jsonDecode(payload);
      if (json.containsKey('gatewayMode')) {
        final GatewayMode? gatewayMode = GatewayModeFromString.fromString(
          json['gatewayMode'],
        );
        if (gatewayMode == null) {
          return Response.badRequest(
            body: {'message': '${json["gatewayMode"]} is not a gateway mode'},
          );
        }
        await _controller.updateGatewayMode(gatewayMode);
      }
      if (json.containsKey('webUiPath')) {
        final webUiPath = json['webUiPath'].toString();
        // Check path is valid
        final _ = File.fromUri(Uri.file(webUiPath));
        await _webUIService.serveFolderAtPath(webUiPath);
      }
      if (json.containsKey('logLevel')) {
        await _controller.updateLogLevel(json['logLevel']);
      }
      if (json.containsKey('weightFlowMultiplier')) {
        final value = json['weightFlowMultiplier'];
        if (value is num) {
          await _controller.setWeightFlowMultiplier(value.toDouble());
        } else {
          return Response.badRequest(
            body: {'message': 'weightFlowMultiplier must be a number'},
          );
        }
      }
      if (json.containsKey('volumeFlowMultiplier')) {
        final value = json['volumeFlowMultiplier'];
        if (value is num) {
          await _controller.setVolumeFlowMultiplier(value.toDouble());
        } else {
          return Response.badRequest(
            body: {'message': 'volumeFlowMultiplier must be a number'},
          );
        }
      }
      if (json.containsKey('scalePowerMode')) {
        final ScalePowerMode? mode = ScalePowerModeFromString.fromString(
          json['scalePowerMode'],
        );
        if (mode == null) {
          return Response.badRequest(
            body: {
              'message':
                  '${json["scalePowerMode"]} is not a valid scale power mode',
            },
          );
        }
        await _controller.setScalePowerMode(mode);
      }
      if (json.containsKey('preferredMachineId')) {
        final value = json['preferredMachineId'];
        if (value == null || value is String) {
          await _controller.setPreferredMachineId(value);
        } else {
          return Response.badRequest(
            body: {'message': 'preferredMachineId must be a string or null'},
          );
        }
      }
      if (json.containsKey('preferredScaleId')) {
        final value = json['preferredScaleId'];
        if (value == null || value is String) {
          await _controller.setPreferredScaleId(value);
        } else {
          return Response.badRequest(
            body: {'message': 'preferredScaleId must be a string or null'},
          );
        }
      }
      if (json.containsKey('defaultSkinId')) {
        final value = json['defaultSkinId'];
        if (value is String) {
          try {
            await _webUIStorage.setDefaultSkin(value);
          } catch (e) {
            return Response.badRequest(
              body: {'message': 'Invalid skin ID: ${e.toString()}'},
            );
          }
        } else {
          return Response.badRequest(
            body: {'message': 'defaultSkinId must be a string'},
          );
        }
      }
      if (json.containsKey('automaticUpdateCheck')) {
        final value = json['automaticUpdateCheck'];
        if (value is bool) {
          await _controller.setAutomaticUpdateCheck(value);
        } else {
          return Response.badRequest(
            body: {'message': 'automaticUpdateCheck must be a boolean'},
          );
        }
      }
      if (json.containsKey('chargingMode')) {
        final mode = ChargingModeFromString.fromString(json['chargingMode']);
        if (mode == null) {
          return Response.badRequest(
            body: {'message': '${json["chargingMode"]} is not a valid charging mode'},
          );
        }
        await _controller.setChargingMode(mode);
      }
      if (json.containsKey('nightModeEnabled')) {
        final value = json['nightModeEnabled'];
        if (value is bool) {
          await _controller.setNightModeEnabled(value);
        } else {
          return Response.badRequest(
            body: {'message': 'nightModeEnabled must be a boolean'},
          );
        }
      }
      if (json.containsKey('nightModeSleepTime')) {
        final value = json['nightModeSleepTime'];
        if (value is int && value >= 0 && value < 1440) {
          await _controller.setNightModeSleepTime(value);
        } else {
          return Response.badRequest(
            body: {'message': 'nightModeSleepTime must be an integer 0-1439'},
          );
        }
      }
      if (json.containsKey('nightModeMorningTime')) {
        final value = json['nightModeMorningTime'];
        if (value is int && value >= 0 && value < 1440) {
          await _controller.setNightModeMorningTime(value);
        } else {
          return Response.badRequest(
            body: {'message': 'nightModeMorningTime must be an integer 0-1439'},
          );
        }
      }
      return Response.ok('');
    });

    // Adding logs here, even though they aren't part of Settings
    app.get('/ws/v1/logs', _handleLogsRequest);
  }

  Future<Response> _handleLogsRequest(Request req) async {
    return sws.webSocketHandler((WebSocketChannel socket, String? protocol) {
      StreamSubscription? sub;
      sub = Logger.root.onRecord.listen((logRecord) {
        socket.sink.add(
          jsonEncode({
            'level': logRecord.level.name,
            'timestamp': logRecord.time.toIso8601String(),
            'name': logRecord.loggerName,
            'message': logRecord.message,
          }),
        );
      });
      socket.stream.listen(
        (msg) {
          // handle incoming messages if needed
        },
        onDone: () {
          sub?.cancel();
        },
        onError: (e, _) {
          sub?.cancel();
        },
      );
    })(req);
  }
}
