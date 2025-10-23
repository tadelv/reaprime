part of '../webserver_service.dart';

class DevicesHandler {
  final DeviceController _controller;

  DevicesHandler({required DeviceController controller})
    : _controller = controller;

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
    app.get('/api/v1/devices/scan', () async {
      await _controller.scanForDevices();

      return await _deviceList();
    });
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
}
