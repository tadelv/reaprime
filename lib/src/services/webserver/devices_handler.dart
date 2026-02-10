part of '../webserver_service.dart';

class DevicesHandler {
  final DeviceController _controller;
  final De1Controller _de1Controller;
  final ScaleController _scaleController;

  DevicesHandler({
    required DeviceController controller,
    required De1Controller de1Controller,
    required ScaleController scaleController,
  }) : _controller = controller,
       _de1Controller = de1Controller,
       _scaleController = scaleController;

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

  Future<Response> _handleConnect(Request req) async {
    final devices = _controller.devices;
    final deviceId = req.requestedUri.queryParameters['deviceId'];
    if (deviceId == null) {
      return Response.badRequest();
    }
    final device = devices.firstWhereOrNull((e) => e.deviceId == deviceId);
    if (device == null) {
      return Response.notFound(null);
    }
    switch (device.type) {
      case DeviceType.machine:
        await _de1Controller.connectToDe1(device as De1Interface);
      case DeviceType.scale:
        await _scaleController.connectToScale(device as Scale);
      case DeviceType.sensor:
        await (device as Sensor).onConnect();
    }
    return Response.ok(null);
  }

  Future<Response> _handleDisconnect(Request req) async {
    final devices = _controller.devices;
    final deviceId = req.requestedUri.queryParameters['deviceId'];
    if (deviceId == null) {
      return Response.badRequest();
    }
    final device = devices.firstWhereOrNull((e) => e.deviceId == deviceId);
    if (device == null) {
      return Response.notFound(null);
    }
    await device.disconnect();

    return Response.ok(null);
  }
}
