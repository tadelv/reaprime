part of '../webserver_service.dart';

/// Aggregates device, scanning, and charging state into a single broadcast
/// stream. One instance is shared across all WebSocket connections, avoiding
/// duplicate subscriptions and ensuring correct cleanup when devices
/// appear/disappear.
class DevicesStateAggregator {
  final DeviceController _controller;
  final BatteryController? _batteryController;
  final Logger _log = Logger("DevicesStateAggregator");

  final List<StreamSubscription> _subscriptions = [];

  /// Per-device connectionState subscriptions keyed by deviceId.
  /// Stores both the Device reference (for identity comparison) and the
  /// subscription so we can detect same-ID-different-object replacements.
  final Map<String, (Device, StreamSubscription)> _deviceStateSubs = {};

  final BehaviorSubject<Map<String, dynamic>> _stateStream =
      BehaviorSubject<Map<String, dynamic>>();

  Timer? _debounceTimer;

  /// Broadcast stream of unified state snapshots.
  Stream<Map<String, dynamic>> get stateStream => _stateStream.stream;

  /// Number of active per-device connectionState subscriptions (for testing).
  int get activeDeviceSubscriptionCount => _deviceStateSubs.length;

  DevicesStateAggregator({
    required DeviceController controller,
    BatteryController? batteryController,
  })  : _controller = controller,
        _batteryController = batteryController {
    _start();
  }

  void _start() {
    // Subscribe to device list changes (skip initial BehaviorSubject replay;
    // initial state is sent via the seeded emitState below)
    _subscriptions.add(_controller.deviceStream.skip(1).listen((devices) {
      _updateDeviceSubscriptions(devices);
      _emitState();
    }));

    // Subscribe to scanning state changes (skip initial replay)
    _subscriptions.add(
      _controller.scanningStream.skip(1).listen((_) => _emitState()),
    );

    // Subscribe to charging state changes (skip initial replay)
    if (_batteryController != null) {
      _subscriptions.add(
        _batteryController.chargingState.skip(1).listen((_) => _emitState()),
      );
    }

    // Set up initial per-device subscriptions
    _updateDeviceSubscriptions(_controller.devices);

    // Emit initial state immediately (no debounce)
    _emitState(immediate: true);
  }

  void _updateDeviceSubscriptions(List<Device> devices) {
    final currentIds = devices.map((d) => d.deviceId).toSet();

    // Remove subscriptions for devices no longer in the list
    final staleIds =
        _deviceStateSubs.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in staleIds) {
      _deviceStateSubs.remove(id)?.$2.cancel();
    }

    // Add or replace subscriptions for devices in the list
    for (final device in devices) {
      final existing = _deviceStateSubs[device.deviceId];
      if (existing != null) {
        // Same ID exists — check if it's the same object instance
        if (identical(existing.$1, device)) {
          continue; // Same object, subscription is still valid
        }
        // Different object with same ID (BLE reconnect) — replace subscription
        existing.$2.cancel();
      }
      // New device or replacement: subscribe (skip initial replay — the
      // current state is already captured by _buildSnapshot)
      final sub =
          device.connectionState.skip(1).listen((_) => _emitState());
      _deviceStateSubs[device.deviceId] = (device, sub);
    }
  }

  void _emitState({bool immediate = false}) {
    if (immediate) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _emitStateNow();
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: 100), () {
      _emitStateNow();
    });
  }

  void _emitStateNow() async {
    try {
      final snapshot = await _buildSnapshot();
      _stateStream.add(snapshot);
    } catch (e, st) {
      _log.warning("failed to build devices state snapshot", e, st);
    }
  }

  Future<Map<String, dynamic>> _buildSnapshot() async {
    final devices = _controller.devices;
    final devList = <Map<String, String>>[];
    for (var device in devices) {
      var state = await device.connectionState.first;
      devList.add({
        'name': device.name,
        'id': device.deviceId,
        'state': state.name,
        'type': device.type.name,
      });
    }

    final snapshot = <String, dynamic>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'devices': devList,
      'scanning': _controller.isScanning,
    };
    if (_batteryController?.currentChargingState != null) {
      snapshot['charging'] =
          _batteryController!.currentChargingState!.toJson();
    }
    return snapshot;
  }

  void dispose() {
    _debounceTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    for (final entry in _deviceStateSubs.values) {
      entry.$2.cancel();
    }
    _deviceStateSubs.clear();
    _stateStream.close();
  }
}

class DevicesHandler {
  final DeviceController _controller;
  final De1Controller _de1Controller;
  final ScaleController _scaleController;
  final Logger _log = Logger("Devices handler");
  final DevicesStateAggregator _aggregator;

  DevicesHandler({
    required DeviceController controller,
    required De1Controller de1Controller,
    required ScaleController scaleController,
    BatteryController? batteryController,
  })  : _controller = controller,
        _de1Controller = de1Controller,
        _scaleController = scaleController,
        _aggregator = DevicesStateAggregator(
          controller: controller,
          batteryController: batteryController,
        );

  void dispose() {
    _aggregator.dispose();
  }

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

  // -- WebSocket handler --

  void _handleDevicesSocket(WebSocketChannel socket, String? protocol) {
    _log.fine("devices websocket connected");

    // Subscribe to the shared aggregator stream — each WebSocket connection
    // gets a lightweight listener on the single broadcast output instead of
    // creating its own set of upstream subscriptions.
    final sub = _aggregator.stateStream.listen((snapshot) {
      try {
        socket.sink.add(jsonEncode(snapshot));
      } catch (e, st) {
        _log.warning("failed to send devices state to websocket", e, st);
      }
    });

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
        sub.cancel();
      },
      onError: (e, st) {
        _log.warning("devices websocket error", e, st);
        sub.cancel();
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

