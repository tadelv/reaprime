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
            'scaleCalibration',
          ]);
        }
        return jsonOk({'capabilities': caps});
      });
    });

    // Scale calibration — Bengle two-point integrated-scale load-cell
    // wizard. `command`: zero (empty platform) | left / right (latch the known
    // `grams` reference mass on that half; both required) | abort.
    app.post('/api/v1/machine/scale/calibrate', (Request r) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'scale calibration not supported'});
        }
        final json = jsonDecode(await r.readAsString());
        if (json is! Map) {
          return jsonBadRequest({'error': 'expected a JSON object body'});
        }
        final command = json['command'];
        switch (command) {
          case 'zero':
            return jsonOk((await de1.calibrateScaleZero()).toJson());
          case 'left':
            if (json['grams'] == null) {
              return jsonBadRequest({
                'error': 'weight calibration requires "grams"',
              });
            }
            return jsonOk(
              (await de1.calibrateScaleWeightLeft(
                parseDouble(json['grams']),
              )).toJson(),
            );
          case 'right':
            if (json['grams'] == null) {
              return jsonBadRequest({
                'error': 'weight calibration requires "grams"',
              });
            }
            return jsonOk(
              (await de1.calibrateScaleWeightRight(
                parseDouble(json['grams']),
              )).toJson(),
            );
          case 'abort':
            await de1.abortScaleCalibration();
            return jsonAccepted();
          default:
            return jsonBadRequest({
              'error':
                  'unknown command "$command" — expected '
                  'zero, left, right, or abort',
            });
        }
      });
    });

    app.get('/api/v1/machine/cupWarmer', (Request _) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'cupWarmer not supported'});
        }
        final t = await de1.getCupWarmerTemperature();
        // Live mat temperature (MatCurrentTemp, read-only). `null` = no
        // valid reading or older firmware without the register — clients
        // render a placeholder, never fake data.
        final current = await de1.getCupWarmerCurrentTemperature();
        // Scheduled pre-warm (MatPreheatEnable/LeadMin, persisted settings)
        // and the read-only MatPreheatActive status ("the SCHEDULE is driving
        // the mat right now" — the answer to why the warmer came on by
        // itself). All three are `null` on firmware without the registers:
        // "unavailable", never faked.
        final prewarm = await de1.getCupWarmerPrewarm();
        final prewarmActive = await de1.getCupWarmerPrewarmActive();
        return jsonOk({
          'temperature': t,
          'currentTemperature': current,
          'prewarmEnabled': prewarm?.enabled,
          'prewarmLeadMinutes': prewarm?.leadMinutes,
          'prewarmActive': prewarmActive,
        });
      });
    });

    app.put('/api/v1/machine/cupWarmer', (Request r) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'cupWarmer not supported'});
        }
        final json = jsonDecode(await r.readAsString());
        if (json is! Map) {
          return jsonBadRequest({'error': 'expected a JSON object body'});
        }
        // `prewarmActive` is READ-ONLY (firmware status): silently ignored in
        // a request body, never written — like currentTemperature.
        final hasTemperature = json['temperature'] != null;
        final hasPrewarm =
            json['prewarmEnabled'] != null || json['prewarmLeadMinutes'] != null;
        if (!hasTemperature && !hasPrewarm) {
          return jsonBadRequest({
            'error':
                'temperature required (or prewarmEnabled / '
                'prewarmLeadMinutes)',
          });
        }

        double? t;
        if (hasTemperature) {
          t = parseDouble(json['temperature']);
          if (t < 0.0 || t > 80.0) {
            return jsonBadRequest({
              'error': 'temperature out of range 0.0-80.0',
            });
          }
        }

        // Pre-warm is a PAIR of firmware registers written together, so a
        // partial request needs the other half: take it from the machine's
        // current (persisted) state, falling back to the firmware defaults.
        bool? prewarmEnabled;
        int? prewarmLeadMinutes;
        if (hasPrewarm) {
          final enabledRaw = json['prewarmEnabled'];
          if (enabledRaw != null && enabledRaw is! bool) {
            return jsonBadRequest({'error': 'prewarmEnabled must be a boolean'});
          }
          final leadRaw = json['prewarmLeadMinutes'];
          int? lead;
          if (leadRaw != null) {
            lead = leadRaw is int ? leadRaw : int.tryParse('$leadRaw');
            if (lead == null) {
              return jsonBadRequest({
                'error': 'prewarmLeadMinutes must be an integer',
              });
            }
            if (lead < 0 || lead > 120) {
              return jsonBadRequest({
                'error': 'prewarmLeadMinutes out of range 0-120',
              });
            }
          }
          final currentPrewarm = await de1.getCupWarmerPrewarm();
          prewarmEnabled = enabledRaw as bool? ?? currentPrewarm?.enabled ?? false;
          prewarmLeadMinutes =
              lead ?? currentPrewarm?.leadMinutes ?? 30; // FW default
        }

        if (t != null) {
          await de1.setCupWarmerTemperature(t);
        }
        if (prewarmEnabled != null && prewarmLeadMinutes != null) {
          await de1.setCupWarmerPrewarm(prewarmEnabled, prewarmLeadMinutes);
        }

        if (!hasPrewarm) {
          return jsonOk({'status': 'accepted'});
        }
        // Never claim a success we cannot verify: on firmware without the
        // registers the writes above landed in unmapped space and did nothing,
        // so echo what the machine actually reports back (`null` = the
        // firmware does not support pre-warm).
        final applied = await de1.getCupWarmerPrewarm();
        return jsonOk({
          'status': 'accepted',
          'prewarmEnabled': applied?.enabled,
          'prewarmLeadMinutes': applied?.leadMinutes,
        });
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

    // Live colour preview: show a colour on the strip now (regardless of
    // awake/sleep) without changing the stored palette — body { front, back }
    // as 12-char hex. `/clear` restores the cached awake palette.
    app.post('/api/v1/machine/ledStrip/preview', (Request r) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'ledStrip not supported'});
        }
        final json = jsonDecode(await r.readAsString());
        if (json is! Map) {
          return jsonBadRequest({'error': 'invalid JSON body'});
        }
        await de1.previewLedColor(
          Color16.fromJson(json['front']),
          Color16.fromJson(json['back']),
        );
        return jsonAccepted();
      });
    });

    app.post('/api/v1/machine/ledStrip/preview/clear', (Request _) async {
      return withDe1((de1) async {
        if (de1 is! BengleInterface) {
          return jsonNotFound({'error': 'ledStrip not supported'});
        }
        await de1.clearLedPreview();
        return jsonAccepted();
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

    app.post('/api/v1/machine/firmware', (Request request) async {
      final List<int> bodyBytes = await request
          .read()
          .expand((x) => x)
          .toList();
      final Uint8List fwImage = Uint8List.fromList(bodyBytes);

      De1Interface de1;
      try {
        de1 = _controller.connectedDe1();
      } catch (e) {
        return jsonError({'error': e.toString()});
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
      return jsonError({'error': e.toString(), 'st': st.toString()});
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

  Future<void> _handleShotSettings(
    WebSocketChannel socket,
    String? protocol,
  ) async {
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

  Future<void> _handleWaterLevels(
    WebSocketChannel socket,
    String? protocol,
  ) async {
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

  Future<void> _handleRawSocket(
    WebSocketChannel socket,
    String? protocol,
  ) async {
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
