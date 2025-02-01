part of '../webserver_service.dart';

class DevicesHandler {
  final DeviceController _controller;

  DevicesHandler({required DeviceController controller})
      : _controller = controller;

  addRoutes(RouterPlus app) {
    app.get('/api/v1/devices', () async {
      log.info("handling devices");
      try {
        var devices = _controller.devices;
        var devMap = [];
        for (var device in devices) {
          var state = await device.connectionState.first;
          devMap.add({
            'id': device.deviceId,
            'state': state.name,
          });
        }
        return devMap;
      } catch (e, st) {
        return Response.internalServerError(
            body: {'e': e.toString(), 'st': st.toString()});
      }
    });
    app.get('/api/v1/devices/scan', () async {
      await _controller.scanForDevices();
      return Response.ok('');
    });
  }
}
