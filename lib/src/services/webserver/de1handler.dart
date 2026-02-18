part of '../webserver_service.dart';

class De1Handler {
  final De1Controller _controller;
  final log = Logger("De1WebHandler");

  De1Handler({required De1Controller controller}) : _controller = controller;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/machine/info', _infoHandler);
    app.get('/api/v1/machine/state', _stateHandler);
    app.put('/api/v1/machine/state/<newState>', _requestStateHandler);
    app.post('/api/v1/machine/profile', _profileHandler);
    app.options('/api/v1/machine/profile', (Request r) {
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
    app.post('/api/v1/machine/shotSettings', _shotSettingsHandler);

    // Sockets
    app.get('/ws/v1/machine/snapshot', sws.webSocketHandler(_handleSnapshot));
    app.get(
      '/ws/v1/machine/shotSettings',
      sws.webSocketHandler(_handleShotSettings),
    );
    app.get(
      '/ws/v1/machine/waterLevels',
      sws.webSocketHandler(_handleWaterLevels),
    );
    app.get('/ws/v1/machine/raw', sws.webSocketHandler(_handleRawSocket));

    app.post('/api/v1/machine/waterLevels', (Request r) async {
      return withDe1((de1) async {
        var json = jsonDecode(await r.readAsString());
        if (json['refillLevel'] != null) {
          await de1.setRefillLevel(json['refillLevel']);
        }
        return Response(202);
      });
    });

    // MMR?

    app.post('/api/v1/machine/settings', (Request r) async {
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
        if (json['steamPurgeMode'] != null) {
          await de1.setSteamPurgeMode(parseInt(json['steamPurgeMode']));
        }

        return Response(202);
      });
    });

    app.get('/api/v1/machine/settings', () async {
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
        json['steamPurgeMode'] = await de1.getSteamPurgeMode();
        return Response.ok(jsonEncode(json));
      });
    });

    app.post('/api/v1/machine/settings/advanced', (Request r) async {
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

    app.get('/api/v1/machine/settings/advanced', () async {
      return withDe1((de1) async {
        var json = <String, dynamic>{};
        json['heaterPh1Flow'] = await de1.getHeaterPhase1Flow();
        json['heaterPh2Flow'] = await de1.getHeaterPhase2Flow();
        json['heaterIdleTemp'] = await de1.getHeaterIdleTemp();
        json['heaterPh2Timeout'] = await de1.getHeaterPhase2Timeout();
        return Response.ok(jsonEncode(json));
      });
    });

    app.get('/api/v1/machine/calibration', () async {
      return withDe1((de1) async {
        var json = <String, dynamic>{};
        json['flowMultiplier'] = await de1.getFlowEstimation();
        return Response.ok(jsonEncode(json));
      });
    });

    app.post('/api/v1/machine/calibration', (Request r) async {
      return withDe1((de1) async {
        var json = jsonDecode(await r.readAsString());
        if (json['flowMultiplier'] != null) {
          await de1.setFlowEstimation(parseDouble(json['flowMultiplier']));
        }
        return Response(202);
      });
    });

    app.post('/api/v1/machine/firmware', (Request request) async {
      final List<int> bodyBytes =
          await request.read().expand((x) => x).toList();
      final Uint8List fwImage = Uint8List.fromList(bodyBytes);

      De1Interface de1;
      try {
        de1 = _controller.connectedDe1();
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
        );
      }

      final progressController = StreamController<List<int>>();

      void emit(Map<String, dynamic> event) {
        if (!progressController.isClosed) {
          progressController.add(utf8.encode('${jsonEncode(event)}\n'));
        }
      }

      // When the client disconnects, dart:io unsubscribes from the stream.
      // Detect this via onCancel and abort the upload.
      progressController.onCancel = () async {
        log.warning('firmware upload: client disconnected, cancelling');
        await de1.cancelFirmwareUpload();
      };

      emit({'status': 'erasing', 'progress': 0.0});

      double lastProgress = -1;

      de1
          .updateFirmware(
            fwImage,
            onProgress: (progress) {
              if (progress - lastProgress < 0.01) {
                return;
              }
              lastProgress = progress;
              emit({'status': 'uploading', 'progress': progress});
            },
          )
          .then((_) {
            emit({'status': 'done', 'progress': 1.0});
            progressController.close();
          })
          .catchError((Object e) {
            // Cancelled uploads throw — emit error only if stream still open
            emit({'status': 'error', 'progress': -1.0, 'error': e.toString()});
            progressController.close();
          });

      return Response.ok(
        progressController.stream,
        headers: {'Content-Type': 'application/x-ndjson'},
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

  void _withDe1Ws(
    WebSocketChannel socket,
    void Function(De1Interface) body,
  ) {
    De1Interface de1;
    try {
      de1 = _controller.connectedDe1();
    } catch (e) {
      socket.sink.add(jsonEncode({'error': 'No machine connected'}));
      socket.sink.close();
      return;
    }
    body(de1);
  }

  Future<Response> _infoHandler(Request request) async {
    return withDe1((De1Interface de1) async {
      return Response.ok(jsonEncode(de1.machineInfo.toJson()));
    });
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

  _handleSnapshot(WebSocketChannel socket, String? protocol) async {
    log.fine("handling websocket connection");
    _withDe1Ws(socket, (de1) {
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
    });
  }

  _handleShotSettings(WebSocketChannel socket, String? protocol) async {
    log.fine('handling shot settings connection');
    _withDe1Ws(socket, (de1) {
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
    });
  }

  _handleWaterLevels(WebSocketChannel socket, String? protocol) async {
    log.fine('handling water levels connection');
    _withDe1Ws(socket, (de1) {
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
    });
  }

  _handleRawSocket(WebSocketChannel socket, String? protocol) async {
    _withDe1Ws(socket, (de1) {
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
    });
  }
}

