part of '../webserver_service.dart';

class De1Handler {
  final De1Controller _controller;
  final log = Logger("De1WebHandler");

  De1Handler({required De1Controller controller}) : _controller = controller;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/de1/state', _stateHandler);
    app.put('/api/v1/de1/state/<newState>', _requestStateHandler);
    app.post('/api/v1/de1/profile', _profileHandler);
    app.options('/api/v1/de1/profile', (Request r) {
      return Response.ok(
        '',
        headers: {
          'Access-Control-Allow-Origin': '*', // or specify a particular origin
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers':
              'Origin, Content-Type, Accept, Authorization',
          // Optionally, add the following if you need to allow credentials:
          // 'Access-Control-Allow-Credentials': 'true',
          // And you may also include a max age:
          // 'Access-Control-Max-Age': '3600'
        },
      );
    });
    app.post('/api/v1/de1/shotSettings', _shotSettingsHandler);

    // Sockets
    app.get('/ws/v1/de1/snapshot', sws.webSocketHandler(_handleSnapshot));
    app.get(
      '/ws/v1/de1/shotSettings',
      sws.webSocketHandler(_handleShotSettings),
    );
    app.get('/ws/v1/de1/waterLevels', sws.webSocketHandler(_handleWaterLevels));
    app.get('/ws/v1/de1/raw', sws.webSocketHandler(_handleRawSocket));

    app.post('/api/v1/de1/waterLevels', (Request r) async {
      return withDe1((de1) async {
        var json = jsonDecode(await r.readAsString());
        if (json['warningThresholdPercentage'] != null) {
          await de1.setWaterLevelWarning(json['warningThresholdPercentage']);
        }
        return Response(202);
      });
    });

    // MMR?

    app.post('/api/v1/de1/settings', (Request r) async {
      return withDe1((de1) async {
        var json = jsonDecode(await r.readAsString());
        log.info("have: $json");
        if (json['usb'] != null) {
          await de1.setUsbChargerMode(json['usb'] == 'enable');
        }
        if (json['fan'] != null) {
          await de1.setFanThreshhold(parseInt(json['fan']));
        }
        if (json['flushTemp'] != null) {
          await de1.setFlushTemperature(parseDouble(json['flushTemp']));
        }
        if (json['flushFlow'] != null) {
          await de1.setFlushFlow(parseDouble(json['flushFlow']));
        }
        if (json['flushTimeout'] != null) {
          await de1.setFlushTimeout(parseDouble(json['flushTimeout']));
        }
        if (json['hotWaterFlow'] != null) {
          await de1.setHotWaterFlow(parseDouble(json['hotWaterFlow']));
        }
        if (json['steamFlow'] != null) {
          await de1.setSteamFlow(parseDouble(json['steamFlow']));
        }
        if (json['tankTemp'] != null) {
          await de1.setTankTempThreshold(parseInt(json['tankTemp']));
        }

        return Response(202);
      });
    });

    app.get('/api/v1/de1/settings', () async {
      return withDe1((de1) async {
        var json = <String, dynamic>{};
        json['fan'] = await de1.getFanThreshhold();
        json['usb'] = await de1.getUsbChargerMode();
        json['flushTemp'] = await de1.getFlushTemperature();
        json['flushTimeout'] = await de1.getFlushTimeout();
        json['flushFlow'] = await de1.getFlushFlow();
        json['hotWaterFlow'] = await de1.getHotWaterFlow();
        json['steamFlow'] = await de1.getSteamFlow();
        json['tankTemp'] = await de1.getTankTempThreshold();
        return Response.ok(jsonEncode(json));
      });
    });

    app.post('/api/v1/de1/settings/advanced', (Request r) async {
      return withDe1((de1) async {
        var json = jsonDecode(await r.readAsString());
        if (json['heaterPh1Flow'] != null) {
          await de1.setHeaterPhase1Flow(parseDouble(json['heaterPh1Flow']));
        }
        if (json['heaterPh2Flow'] != null) {
          await de1.setHeaterPhase2Flow(parseDouble(json['heaterPh2Flow']));
        }
        if (json['heaterIdleTemp'] != null) {
          await de1.setHeaterIdleTemp(parseDouble(json['heaterIdleTemp']));
        }
        if (json['heaterPh2Timeout'] != null) {
          await de1.setHeaterPhase2Timeout(
            parseDouble(json['heaterPh2Timeout']),
          );
        }
        return Response(202);
      });
    });

    app.get('/api/v1/de1/settings/advanced', () async {
      return withDe1((de1) async {
        var json = <String, dynamic>{};
        json['heaterPh1Flow'] = await de1.getHeaterPhase1Flow();
        json['heaterPh2Flow'] = await de1.getHeaterPhase2Flow();
        json['heaterIdleTemp'] = await de1.getHeaterIdleTemp();
        json['heaterPh2Timeout'] = await de1.getHeaterPhase2Timeout();
        return Response.ok(jsonEncode(json));
      });
    });

    app.post('/api/v1/de1/firmware', (Request request) async {
      try {
        // Read the binary body into a Uint8List
        final List<int> bodyBytes =
            await request.read().expand((x) => x).toList();
        final Uint8List fwImage = Uint8List.fromList(bodyBytes);

        // Send to DE1 (assumes withDe1 returns a response or Future<void>)
        return await withDe1((de1) async {
          await de1.updateFirmware(fwImage, onProgress: (progress) {});
          return Response.ok('Firmware uploaded successfully');
        });
      } catch (e) {
        return Response.internalServerError(
          body: 'Failed to upload firmware: $e',
        );
      }
    });
  }

  Future<Response> withDe1(Future<Response> Function(De1Interface) call) async {
    try {
      var de1 = _controller.connectedDe1();
      return await call(de1);
    } catch (e, st) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString(), 'st': st.toString()}),
      );
    }
  }

  Future<Response> _stateHandler(Request request) async {
    return withDe1((De1Interface de1) async {
      var snapshot = await de1.currentSnapshot.first;
      return Response.ok(jsonEncode(snapshot.toJson()));
    });
  }

  Future<Response> _requestStateHandler(
    Request request,
    String newState,
  ) async {
    return withDe1((de1) async {
      var requestState = MachineState.values.byName(newState);
      await de1.requestState(requestState);
      return Response.ok("");
    });
  }

  Future<Response> _profileHandler(Request request) async {
    return withDe1((de1) async {
      final payload = await request.readAsString();

      Map<String, dynamic> json = jsonDecode(payload);
      Profile profile = Profile.fromJson(json);
      await de1.setProfile(profile);
      return Response.ok("");
    });
  }

  Future<Response> _shotSettingsHandler(Request request) async {
    return withDe1((de1) async {
      final payload = await request.readAsString();

      Map<String, dynamic> json = jsonDecode(payload);
      De1ShotSettings settings = De1ShotSettings.fromJson(json);
      await de1.updateShotSettings(settings);
      return Response.ok("");
    });
  }

  void _handleSnapshot(WebSocketChannel socket, String? _) async {
    log.fine("handling websocket connection");
    var de1 = _controller.connectedDe1();
    var sub = de1.currentSnapshot.listen((snapshot) {
      try {
        var json = jsonEncode(snapshot.toJson());
        socket.sink.add(json);
      } catch (e, st) {
        log.severe("failed to send: ", e, st);
      }
    });
    socket.stream.listen(
      (e) {},
      onDone: () => sub.cancel(),
      onError: (e, st) => sub.cancel(),
    );
  }

  void _handleShotSettings(WebSocketChannel socket, String? _) async {
    log.fine('handling shot settings connection');
    var de1 = _controller.connectedDe1();
    var sub = de1.shotSettings.listen((data) {
      try {
        var json = jsonEncode(data.toJson());
        socket.sink.add(json);
      } catch (e, st) {
        log.severe("failed to send: ", e, st);
      }
    });
    socket.stream.listen(
      (e) {},
      onDone: () => sub.cancel(),
      onError: (e, st) => sub.cancel(),
    );
  }

  void _handleWaterLevels(WebSocketChannel socket, String? _) async {
    log.fine('handling water levels connection');
    var de1 = _controller.connectedDe1();
    var sub = de1.waterLevels.listen((data) {
      try {
        var json = jsonEncode(data.toJson());
        socket.sink.add(json);
      } catch (e, st) {
        log.severe("failed to send water levels", e, st);
      }
    });
    socket.stream.listen(
      (e) {},
      onDone: () => sub.cancel(),
      onError: (e, st) => sub.cancel(),
    );
  }

  void _handleRawSocket(WebSocketChannel socket, String? _) async {
    var de1 = _controller.connectedDe1();
    var sub = de1.rawOutStream.listen((data) {
      try {
        var json = jsonEncode(data.toJson());
        socket.sink.add(json);
      } catch (e) {
        log.severe("Failed to send raw: ", e);
      }
    });
    socket.stream.listen(
      (event) {
        var json = jsonDecode(event.toString());
        final message = De1RawMessage.fromJson(json);
        de1.sendRawMessage(message);
      },
      onDone: () => sub.cancel(),
      onError: (e, st) => sub.cancel(),
    );
  }
}
