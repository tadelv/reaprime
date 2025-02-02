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
    app.put('/api/v1/de1/usb/<state>', _usbChargerHandler);
    app.get('/api/v1/de1/fan', _readFanThreshold);
    app.put('/api/v1/de1/fan', _setFanThreshold);

    // Sockets
    app.get('/ws/v1/de1/snapshot', sws.webSocketHandler(_handleSnapshot));
    app.get(
        '/ws/v1/de1/shotSettings', sws.webSocketHandler(_handleShotSettings));
    app.get('/ws/v1/de1/waterLevels', sws.webSocketHandler(_handleWaterLevels));

    // MMR?
    app.get('/api/v1/de1/settings/flushTemp', () async {
      return withDe1(
        (de1) async {
          var temp = await de1.getFlushTemperature();
          return Response.ok(jsonEncode({'value': temp}));
        },
      );
    });
    app.post('/api/v1/de1/settings/flushTemp', (Request r) async {
      return withDe1(
        (de1) async {
          var data = await r.readAsString();
          var json = jsonDecode(data);
          if (json['value'] is double) {
            await de1.setFlushTemperature(json['value']);
            return Response.ok(jsonEncode({'value': json['value']}));
          }
          return Response.badRequest();
        },
      );
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

  Future<Response> _usbChargerHandler(Request request, String state) async {
    return withDe1(
      (de1) async {
        await de1.setUsbChargerMode(state == "enable");
        return Response.ok('');
      },
    );
  }

  Future<Response> _readFanThreshold() async {
    return withDe1(
      (de1) async {
        var threshold = await de1.getFanThreshhold();
        return Response.ok(jsonEncode({'value': threshold}));
      },
    );
  }

  Future<Response> _setFanThreshold(Request request) async {
    return withDe1(
      (de1) async {
        int temp = (await request.body.asJson)['value'];
        await de1.setFanThreshhold(temp);
        return Response.ok(jsonEncode({'value': temp}));
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
