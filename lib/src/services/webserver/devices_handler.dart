part of '../webserver_service.dart';

class DevicesHandler {
  final DeviceController _controller;
  final De1Controller _de1Controller;
  final ScaleController _scaleController;
  final BatteryController? _batteryController;
  final Logger _log = Logger("Devices handler");

  DevicesHandler({
    required DeviceController controller,
    required De1Controller de1Controller,
    required ScaleController scaleController,
    BatteryController? batteryController,
  }) : _controller = controller,
       _de1Controller = de1Controller,
       _scaleController = scaleController,
       _batteryController = batteryController;

  addRoutes(RouterPlus app) {
    app.get('/api/v1/devices', () async {
      log.info("handling devices");
      try {
        return await _deviceList();
      } catch (e, st) {
        return Response.internalServerError(
          body: {'e': e.toString(), 'st': st.toString()},
        );
      }
    });
    app.get('/api/v1/devices/scan', (Request req) async {
      final bool shouldConnect =
          req.requestedUri.queryParametersAll["connect"]?.firstOrNull == "true";
      final bool quickScan =
          req.requestedUri.queryParametersAll["quick"]?.firstOrNull == "true";
      log.info("running scan, connect = $shouldConnect, quick = $quickScan");
      if (quickScan) {
        _controller.scanForDevices(autoConnect: shouldConnect);
        return [];
      }
      await _controller.scanForDevices(autoConnect: shouldConnect);

      return await _deviceList();
    });

    app.put('/api/v1/devices/connect', _handleConnect);
    app.put('/api/v1/devices/disconnect', _handleDisconnect);

    app.get(
      '/ws/v1/devices',
      sws.webSocketHandler(_handleDevicesSocket),
    );
  }

  Future<List<Map<String, String>>> _deviceList() async {
    var devices = _controller.devices;
    var devMap = <Map<String, String>>[];
    for (var device in devices) {
      var state = await device.connectionState.first;
      devMap.add({
        'name': device.name,
        'id': device.deviceId,
        'state': state.name,
        'type': device.type.name,
      });
    }
    return devMap;
  }

  /// Extract deviceId from JSON body or query parameter.
  /// Body takes precedence; query param is kept for backward compatibility.
  Future<String?> _extractDeviceId(Request req) async {
    try {
      final body = await req.readAsString();
      if (body.isNotEmpty) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final id = json['deviceId'] as String?;
        if (id != null) return id;
      }
    } catch (_) {
      // Not valid JSON — fall through to query parameter
    }
    return req.requestedUri.queryParameters['deviceId'];
  }

  Future<Response> _handleConnect(Request req) async {
    final devices = _controller.devices;
    final deviceId = await _extractDeviceId(req);
    if (deviceId == null) {
      return jsonBadRequest({'error': 'Missing deviceId'});
    }
    final device = devices.firstWhereOrNull((e) => e.deviceId == deviceId);
    if (device == null) {
      return Response.notFound(null);
    }
    await _connectDevice(device);
    return Response.ok(null);
  }

  Future<Response> _handleDisconnect(Request req) async {
    final devices = _controller.devices;
    final deviceId = await _extractDeviceId(req);
    if (deviceId == null) {
      return jsonBadRequest({'error': 'Missing deviceId'});
    }
    final device = devices.firstWhereOrNull((e) => e.deviceId == deviceId);
    if (device == null) {
      return Response.notFound(null);
    }
    await device.disconnect();

    return Response.ok(null);
  }

  void _emitStateNow(WebSocketChannel socket) async {
    try {
      final devices = await _deviceList();
      final state = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'devices': devices,
        'scanning': _controller.isScanning,
      };
      socket.sink.add(jsonEncode(state));
    } catch (e, st) {
      _log.warning("failed to emit devices state", e, st);
    }
  }

  // -- WebSocket handler --

  void _handleDevicesSocket(WebSocketChannel socket, String? protocol) {
    _log.fine("devices websocket connected");

    final subscriptions = <StreamSubscription>[];
    // Track per-device connectionState subscriptions by deviceId
    final deviceStateSubs = <String, StreamSubscription>{};

    // Debounce rapid-fire state changes (scan triggers multiple stream events
    // within <1ms from scanningStream, deviceStream, and per-service updates)
    Timer? debounceTimer;

    void emitState({bool immediate = false}) {
      if (immediate) {
        debounceTimer?.cancel();
        debounceTimer = null;
        _emitStateNow(socket);
        return;
      }
      debounceTimer?.cancel();
      debounceTimer = Timer(Duration(milliseconds: 100), () {
        _emitStateNow(socket);
      });
    }

    void updateDeviceSubscriptions(List<Device> devices) {
      final currentIds = devices.map((d) => d.deviceId).toSet();

      // Remove subscriptions for devices no longer in the list
      final staleIds =
          deviceStateSubs.keys.where((id) => !currentIds.contains(id)).toList();
      for (final id in staleIds) {
        deviceStateSubs.remove(id)?.cancel();
      }

      // Add subscriptions for new devices (skip initial replay — the current
      // state is already captured by emitState())
      for (final device in devices) {
        if (!deviceStateSubs.containsKey(device.deviceId)) {
          deviceStateSubs[device.deviceId] =
              device.connectionState.skip(1).listen((_) => emitState());
        }
      }
    }

    // Subscribe to device list changes (skip initial BehaviorSubject replay;
    // initial state is sent explicitly below)
    subscriptions.add(_controller.deviceStream.skip(1).listen((devices) {
      updateDeviceSubscriptions(devices);
      emitState();
    }));

    // Subscribe to scanning state changes (skip initial replay)
    subscriptions.add(
      _controller.scanningStream.skip(1).listen((_) => emitState()),
    );

    // Set up initial per-device subscriptions
    updateDeviceSubscriptions(_controller.devices);

    // Send initial state immediately (no debounce)
    emitState(immediate: true);

    // Listen for incoming commands
    socket.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message.toString()) as Map<String, dynamic>;
          _handleCommand(data, socket);
        } catch (e) {
          socket.sink.add(jsonEncode({'error': 'Invalid JSON: $e'}));
        }
      },
      onDone: () {
        _log.fine("devices websocket disconnected");
        debounceTimer?.cancel();
        for (final sub in subscriptions) {
          sub.cancel();
        }
        for (final sub in deviceStateSubs.values) {
          sub.cancel();
        }
        deviceStateSubs.clear();
      },
      onError: (e, st) {
        _log.warning("devices websocket error", e, st);
        debounceTimer?.cancel();
        for (final sub in subscriptions) {
          sub.cancel();
        }
        for (final sub in deviceStateSubs.values) {
          sub.cancel();
        }
        deviceStateSubs.clear();
      },
    );
  }

  void _handleCommand(Map<String, dynamic> data, WebSocketChannel socket) {
    final command = data['command'] as String?;
    if (command == null) {
      socket.sink.add(jsonEncode({'error': 'Missing "command" field'}));
      return;
    }

    switch (command) {
      case 'scan':
        final connect = data['connect'] as bool? ?? false;
        final quick = data['quick'] as bool? ?? false;
        _log.fine("ws scan command: connect=$connect, quick=$quick");
        if (quick) {
          _controller.scanForDevices(autoConnect: connect);
        } else {
          _controller.scanForDevices(autoConnect: connect).catchError((e) {
            socket.sink.add(jsonEncode({'error': 'Scan failed: $e'}));
          });
        }

      case 'connect':
        final deviceId = data['deviceId'] as String?;
        if (deviceId == null) {
          socket.sink.add(jsonEncode({'error': 'Missing "deviceId" for connect'}));
          return;
        }
        final device =
            _controller.devices.firstWhereOrNull((e) => e.deviceId == deviceId);
        if (device == null) {
          socket.sink.add(jsonEncode({'error': 'Device not found: $deviceId'}));
          return;
        }
        _connectDevice(device).catchError((e) {
          socket.sink.add(jsonEncode({'error': 'Connect failed: $e'}));
        });

      case 'disconnect':
        final deviceId = data['deviceId'] as String?;
        if (deviceId == null) {
          socket.sink
              .add(jsonEncode({'error': 'Missing "deviceId" for disconnect'}));
          return;
        }
        final device =
            _controller.devices.firstWhereOrNull((e) => e.deviceId == deviceId);
        if (device == null) {
          socket.sink.add(jsonEncode({'error': 'Device not found: $deviceId'}));
          return;
        }
        device.disconnect().catchError((e) {
          socket.sink.add(jsonEncode({'error': 'Disconnect failed: $e'}));
        });

      default:
        socket.sink.add(jsonEncode({'error': 'Unknown command: $command'}));
    }
  }

  Future<void> _connectDevice(Device device) async {
    switch (device.type) {
      case DeviceType.machine:
        await _de1Controller.connectToDe1(device as De1Interface);
      case DeviceType.scale:
        await _scaleController.connectToScale(device as Scale);
      case DeviceType.sensor:
        await (device as Sensor).onConnect();
    }
  }
}
