part of '../webserver_service.dart';

class De1Handler {
  final SettingsController _settingsController;
  final De1Controller _controller;
  final ScaleController _scaleController;
  final WorkflowController _workflowController;
  final log = Logger("De1WebHandler");

  De1Handler({
    required De1Controller controller,
    required SettingsController settingsController,
    required ScaleController scaleController,
    required WorkflowController workflowController,
  }) : _controller = controller,
       _settingsController = settingsController,
       _scaleController = scaleController,
       _workflowController = workflowController;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/machine/info', _infoHandler);
    app.get('/api/v1/machine/state', _stateHandler);
    app.put('/api/v1/machine/state/<newState>', _requestStateHandler);
    app.post('/api/v1/machine/profile', _profileHandler);
    // TODO: is this still needed?
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

    app.get('/api/v1/machine/capabilities', (Request _) async {
      return withDe1((de1) async {
        final caps = <String>[];
        if (de1 is BengleInterface) {
          caps.addAll([
            'cupWarmer',
            'integratedScale',
            'ledStrip',
            'stopAtWeight',
          ]);
        }
        return jsonOk({'capabilities': caps});
      });
    });

    app.get('/api/v1/machine/cupWarmer', (Request _) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'cupWarmer not supported'});
        }
        final t = await de1.getCupWarmerTemperature();
        return jsonOk({'temperature': t});
      });
    });

    app.put('/api/v1/machine/cupWarmer', (Request r) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'cupWarmer not supported'});
        }
        final json = jsonDecode(await r.readAsString());
        if (json is! Map || json['temperature'] == null) {
          return jsonBadRequest({'error': 'temperature required'});
        }
        final t = parseDouble(json['temperature']);
        if (t < 0.0 || t > 80.0) {
          return jsonBadRequest({'error': 'temperature out of range 0.0-80.0'});
        }
        await de1.setCupWarmerTemperature(t);
        return jsonOk({'status': 'accepted'});
      });
    });

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
    app.get(
      '/ws/v1/machine/shotState',
      sws.webSocketHandler(_handleShotState),
    );

    app.get('/api/v1/machine/ledStrip', (Request _) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'ledStrip not supported'});
        }
        final state = await de1.getLedStripState();
        return jsonOk(state.toJson());
      });
    });

    app.put('/api/v1/machine/ledStrip', (Request r) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'ledStrip not supported'});
        }
        final json = jsonDecode(await r.readAsString());
        if (json is! Map) {
          return jsonBadRequest({'error': 'invalid JSON body'});
        }
        final state = LedStripState.fromJson(json as Map<String, dynamic>);
        await de1.setLedStrip(state);
        return jsonOk({'status': 'accepted'});
      });
    });

    app.post('/api/v1/machine/ledStrip/commit', (Request _) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'ledStrip not supported'});
        }
        await de1.commitLedStrip();
        return jsonAccepted();
      });
    });

    app.post('/api/v1/machine/ledStrip/reset', (Request _) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'ledStrip not supported'});
        }
        await de1.resetLedStrip();
        final state = await de1.getLedStripState();
        return jsonOk(state.toJson());
      });
    });

    app.post('/api/v1/machine/waterLevels', (Request r) async {
      return withDe1((de1) async {
        var json = jsonDecode(await r.readAsString());
        if (json['refillLevel'] != null) {
          await de1.setRefillLevel((json['refillLevel'] as num).toInt());
        }
        return jsonAccepted();
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
          await _controller.setFlushFlow(parseDouble(json['flushFlow']));
        }
        if (json['flushTimeout'] != null) {
          await de1.setFlushTimeout(parseDouble(json['flushTimeout']));
        }
        if (json['hotWaterFlow'] != null) {
          await _controller.setHotWaterFlow(parseDouble(json['hotWaterFlow']));
        }
        if (json['steamFlow'] != null) {
          await _controller.setSteamFlow(parseDouble(json['steamFlow']));
        }
        if (json['tankTemp'] != null) {
          await de1.setTankTempThreshold(parseInt(json['tankTemp']));
        }
        if (json['steamPurgeMode'] != null) {
          await de1.setSteamPurgeMode(parseInt(json['steamPurgeMode']));
        }

        return jsonAccepted();
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
        return jsonOk(json);
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
        if (json['heaterVoltage'] != null) {
          await de1.setHeaterVoltage(
            De1HeaterVoltage.fromInt(
              parseInt(json['heaterVoltage']),
            ),
          );
        }
        if (json['refillKitSetting'] != null) {
          await de1.setRefillKitSettings(
            De1RefillKitSettings.values.firstWhere(
              (e) => e.hex == parseInt(json['refillKitSetting']),
            ),
          );
        }
        return jsonAccepted();
      });
    });

    app.get('/api/v1/machine/settings/advanced', () async {
      return withDe1((de1) async {
        var json = <String, dynamic>{};
        json['heaterPh1Flow'] = await de1.getHeaterPhase1Flow();
        json['heaterPh2Flow'] = await de1.getHeaterPhase2Flow();
        json['heaterIdleTemp'] = await de1.getHeaterIdleTemp();
        json['heaterPh2Timeout'] = await de1.getHeaterPhase2Timeout();
        json['heaterVoltage'] = (await de1.getHeaterVoltage()).voltage;
        json['refillKitSetting'] = (await de1.getRefillKitSettings()).hex;
        return jsonOk(json);
      });
    });

    app.get('/api/v1/machine/calibration', () async {
      return withDe1((de1) async {
        var json = <String, dynamic>{};
        json['flowMultiplier'] = await de1.getFlowEstimation();
        return jsonOk(json);
      });
    });

    app.post('/api/v1/machine/calibration', (Request r) async {
      return withDe1((de1) async {
        var json = jsonDecode(await r.readAsString());
        if (json['flowMultiplier'] != null) {
          await de1.setFlowEstimation(parseDouble(json['flowMultiplier']));
        }
        return jsonAccepted();
      });
    });

    app.delete('/api/v1/machine/settings/reset', (Request r) async {
      return withDe1((de1) async {
        await _controller.applySettingsDefaults();
        return jsonAccepted();
      });
    });

  }

  Future<Response> withDe1(Future<Response> Function(De1Interface) call) async {
    try {
      var de1 = _controller.connectedDe1();
      return await call(de1);
    } catch (e, st) {
      return jsonError({'error': e.toString(), 'st': st.toString()});
    }
  }

  /// Bind a machine-gated socket to the *currently* connected De1, and RE-BIND
  /// it whenever [De1Controller] swaps the instance.
  ///
  /// The previous implementation resolved `connectedDe1()` once, at socket
  /// open, and subscribed to that object's streams for the life of the socket.
  /// A machine power-cycle makes De1Controller drop the De1 and build a
  /// brand-new instance (`_onDisconnect()` → next scan → `connectToDe1`), so
  /// the socket stayed bound to the dead object: no frames, and — because the
  /// old instance's transport subjects are only closed by `dispose()`, not
  /// `disconnect()` — no close either. The socket went open-but-silent
  /// forever, and a client whose reconnect logic only triggers on *close*
  /// (`ReconnectingWebSocket`, i.e. every Streamline/WebUI client) never
  /// recovered without a reload. Bench bug i14.
  ///
  /// This follows the pattern `ScaleHandler._handleSnapshot` already uses:
  /// watch the controller, cancel the payload subscription when the device
  /// goes away, and re-attach it to the new device when one arrives. Frames
  /// simply resume — no client-side action, and it heals every client, not
  /// just the one skin.
  ///
  /// Two deliberate choices:
  ///  * **Instance identity, not deviceId, is the swap signal.** The USB
  ///    stable id is byte-identical across a power-cycle
  ///    (`usb-2e8a-a-<factory serial>`), so an id comparison would see "same
  ///    machine" and never re-bind. `identical()` is also what keeps a
  ///    duplicate emission of the *same* De1 from double-subscribing (which
  ///    would double the frame rate).
  ///  * **No `{"status": ...}` frames.** Unlike the scale socket, the machine
  ///    sockets carry a single typed payload (a MachineSnapshot /
  ///    De1ShotSettings / De1WaterLevels per frame) and existing clients parse
  ///    every frame as that type; injecting a status frame would be a
  ///    breaking change to the wire contract. Link state is already published,
  ///    instance-independently, on `/ws/v1/devices`.
  ///
  /// The "no machine at open" contract is unchanged: error frame + close, so
  /// a client's reconnect loop keeps polling until a machine appears.
  void _withDe1Ws(
    WebSocketChannel socket,
    StreamSubscription<dynamic> Function(De1Interface de1) attach, {
    void Function(De1Interface de1, dynamic message)? onMessage,
  }) {
    if (_controller.connectedDe1OrNull == null) {
      socket.sink.add(jsonEncode({'error': 'No machine connected'}));
      socket.sink.close();
      return;
    }

    De1Interface? attached;
    StreamSubscription<dynamic>? payloadSub;

    void detach() {
      final sub = payloadSub;
      payloadSub = null;
      attached = null;
      sub?.cancel();
    }

    final de1Sub = _controller.de1.listen((de1) {
      if (de1 == null) {
        // Machine gone. Stop streaming but hold the socket open: the client
        // keeps its subscription and starts receiving again the moment a
        // machine is back.
        if (attached != null) {
          log.info('machine disconnected — detaching socket until it returns');
          detach();
        }
        return;
      }
      if (identical(de1, attached)) return; // already streaming this instance
      log.info('binding socket to ${de1.name} (${de1.deviceId})');
      detach();
      attached = de1;
      payloadSub = attach(de1);
    });

    socket.stream.listen(
      (message) {
        final de1 = attached;
        if (onMessage == null || de1 == null) return;
        onMessage(de1, message);
      },
      onDone: () {
        de1Sub.cancel();
        detach();
      },
      onError: (Object e, StackTrace st) {
        de1Sub.cancel();
        detach();
      },
    );
  }

  Future<Response> _infoHandler(Request request) async {
    return withDe1((De1Interface de1) async {
      return jsonOk(de1.machineInfo.toJson());
    });
  }

  Future<Response> _stateHandler(Request request) async {
    return withDe1((De1Interface de1) async {
      var snapshot = await de1.currentSnapshot.first;
      return jsonOk(snapshot.toJson());
    });
  }

  Future<Response> _requestStateHandler(
    Request request,
    String newState,
  ) async {
    return withDe1((de1) async {
      var requestState = MachineState.values.byName(newState);
      final blockOnNoScale = _settingsController.blockOnNoScale;
      final scaleConnected =
          _scaleController.currentConnectionState ==
              device.ConnectionState.connected;
      // A cleaning/backflush profile has no yield to weigh, so the no-scale
      // guard never applies to it.
      final isCleaningProfile =
          _workflowController.currentWorkflow.profile.beverageType ==
              BeverageType.cleaning;
      log.fine(
        "Received request to change state to $requestState while scale connected: $scaleConnected, blockOnNoScale: $blockOnNoScale, cleaningProfile: $isCleaningProfile",
      );
      if (requestState == MachineState.espresso &&
          blockOnNoScale &&
          !scaleConnected &&
          !isCleaningProfile) {
        log.warning(
          "Blocking espresso request because no scale detected and blockOnNoScale is enabled",
        );
        return jsonBadRequest({
          'details': 'No scale detected, blocking espresso request',
          'type': 'block_no_scale',
        });
      }
      // Record the intent only for an idle request that (a) targets an
      // active tracked shot — shotState is non-idle only during an espresso
      // shot, never during steam/hot-water/flush — and (b) whose BLE write
      // actually succeeded, so a failed stop can't mislabel a later natural
      // end. This lets the ShotSequencer attribute the stop to apiStop
      // instead of the ambiguous machineEnded bucket.
      final stoppingActiveShot = requestState == MachineState.idle &&
          _controller.currentShotState.state != ShotState.idle;
      await de1.requestState(requestState);
      if (stoppingActiveShot) {
        _controller.recordStopIntent(ShotDecisionReason.apiStop);
      }
      return jsonOk(null);
    });
  }

  Future<Response> _profileHandler(Request request) async {
    return withDe1((de1) async {
      final payload = await request.readAsString();

      Map<String, dynamic> json = jsonDecode(payload);
      Profile profile = Profile.fromJson(json);
      await de1.setProfile(profile);
      return jsonOk(null);
    });
  }

  Future<Response> _shotSettingsHandler(Request request) async {
    return withDe1((de1) async {
      final payload = await request.readAsString();

      Map<String, dynamic> json = jsonDecode(payload);
      De1ShotSettings settings = De1ShotSettings.fromJson(json);
      await de1.updateShotSettings(settings);
      return jsonOk(null);
    });
  }

  /// Streams the shot state + decision feed (see ShotStateEvent). Unlike the
  /// machine-gated sockets this one is NOT behind a connected DE1 — the feed
  /// lives on De1Controller and idles between shots, so clients can attach
  /// once and wait.
  Future<void> _handleShotState(
    WebSocketChannel socket,
    String? protocol,
  ) async {
    log.fine("handling shotState websocket connection");
    var sub = _controller.shotState.listen((event) {
      try {
        socket.sink.add(jsonEncode(event.toJson()));
      } catch (e, st) {
        log.severe("failed to send shotState event: ", e, st);
      }
    });
    socket.stream.listen(
      (e) {},
      onDone: () => sub.cancel(),
      onError: (e, st) => sub.cancel(),
    );
  }

  Future<void> _handleSnapshot(
    WebSocketChannel socket,
    String? protocol,
  ) async {
    log.fine("handling websocket connection");
    _withDe1Ws(socket, (de1) {
      return de1.currentSnapshot.listen((snapshot) {
        try {
          var json = jsonEncode(snapshot.toJson());
          socket.sink.add(json);
        } catch (e, st) {
          log.severe("failed to send: ", e, st);
        }
      });
    });
  }

  Future<void> _handleShotSettings(
    WebSocketChannel socket,
    String? protocol,
  ) async {
    log.fine('handling shot settings connection');
    _withDe1Ws(socket, (de1) {
      return de1.shotSettings.listen((data) {
        try {
          var json = jsonEncode(data.toJson());
          socket.sink.add(json);
        } catch (e, st) {
          log.severe("failed to send: ", e, st);
        }
      });
    });
  }

  Future<void> _handleWaterLevels(
    WebSocketChannel socket,
    String? protocol,
  ) async {
    log.fine('handling water levels connection');
    _withDe1Ws(socket, (de1) {
      return de1.waterLevels.listen((data) {
        try {
          var json = jsonEncode(data.toJson());
          socket.sink.add(json);
        } catch (e, st) {
          log.severe("failed to send water levels", e, st);
        }
      });
    });
  }

  Future<void> _handleRawSocket(
    WebSocketChannel socket,
    String? protocol,
  ) async {
    _withDe1Ws(
      socket,
      (de1) {
        return de1.rawOutStream.listen((data) {
          try {
            var json = jsonEncode(data.toJson());
            socket.sink.add(json);
          } catch (e) {
            log.severe("Failed to send raw: ", e);
          }
        });
      },
      // Writes go to the machine the socket is CURRENTLY bound to, so a raw
      // command sent after a swap reaches the live machine instead of the
      // dead one.
      onMessage: (de1, event) {
        var json = jsonDecode(event.toString());
        final message = De1RawMessage.fromJson(json);
        de1.sendRawMessage(message);
      },
    );
  }
}
