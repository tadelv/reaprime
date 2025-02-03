part of '../webserver_service.dart';

class De1Handler {
  final De1Controller _controller;
  final log = Logger("De1WebHandler");

  De1Handler({required De1Controller controller}) : _controller = controller;

  addRoutes(RouterPlus app) {
    app.get('/api/v1/de1/state', _stateHandler);
    app.put('/api/v1/de1/state/<newState>', _requestStateHandler);
    app.post('/api/v1/de1/profile', _profileHandler);
    app.post('/api/v1/de1/shotSettings', _shotSettingsHandler);

    // Sockets
    app.get('/ws/v1/de1/snapshot', sws.webSocketHandler(_handleSnapshot));
    app.get(
        '/ws/v1/de1/shotSettings', sws.webSocketHandler(_handleShotSettings));
    app.get('/ws/v1/de1/waterLevels', sws.webSocketHandler(_handleWaterLevels));

    // MMR?

    app.post('/api/v1/de1/settings', (Request r) async {
      return withDe1((de1) async {
        var json = jsonDecode(await r.readAsString());
        if (json['usb'] != null) {
          await de1.setUsbChargerMode(json['usb'] == 'enable');
        }
        if (json['fan'] != null) await de1.setFanThreshhold(json['fan']);
        if (json['flushTemp'] != null) {
          await de1.setFlushTemperature(json['flushTemp']);
        }
        if (json['flushFlow'] != null) {
          await de1.setFlushFlow(json['flushFlow']);
        }
        if (json['flushTimeout'] != null) {
          await de1.setFlushTimeout(json['flushTimeout']);
        }
        if (json['hotWaterFlow'] != null) {
          await de1.setHotWaterFlow(json['hotWaterFlow']);
        }
        if (json['steamFlow'] != null) {
          await de1.setSteamFlow(json['steamFlow']);
        }
        if (json['tankTemp'] != null) {
          await de1.setTankTempThreshold(json['tankTemp']);
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
      var charger = await de1.getUsbChargerMode();
      return Response.ok(
        jsonEncode({
          'snapshot': snapshot.toJson(),
          'usbChargerEnabled': charger,
        }),
      );
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
    return withDe1(
      (de1) async {
        final payload = await request.readAsString();

        Map<String, dynamic> json = jsonDecode(payload);
        Profile profile = Profile.fromJson(json);
        await de1.setProfile(profile);
        return Response.ok("");
      },
    );
  }

  Future<Response> _shotSettingsHandler(Request request) async {
    return withDe1(
      (de1) async {
        final payload = await request.readAsString();

        Map<String, dynamic> json = jsonDecode(payload);
        De1ShotSettings settings = De1ShotSettings.fromJson(json);
        await de1.updateShotSettings(settings);
        return Response.ok("");
      },
    );
  }

  _handleSnapshot(WebSocketChannel socket) async {
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

  _handleShotSettings(WebSocketChannel socket) async {
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

  _handleWaterLevels(WebSocketChannel socket) async {
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
}
