part of '../webserver_service.dart';

class SettingsHandler {
  final SettingsController _controller;
  final WebUIService _webUIService;
  final WebUIStorage _webUIStorage;

  SettingsHandler({
    required SettingsController controller,
    required WebUIService service,
    required WebUIStorage webUIStorage,
  }) : _controller = controller,
       _webUIService = service,
       _webUIStorage = webUIStorage;

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
      return {
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
      };
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
