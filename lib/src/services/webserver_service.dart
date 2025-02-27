import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'dart:convert';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart' as sws;

part 'webserver/de1handler.dart';
part 'webserver/scale_handler.dart';
part 'webserver/devices_handler.dart';

final log = Logger("Webservice");

Future<void> startWebServer(
  DeviceController deviceController,
  De1Controller de1Controller,
  ScaleController scaleController,
) async {
  log.info("starting webserver");
  final de1Handler = De1Handler(controller: de1Controller);
  final scaleHandler = ScaleHandler(controller: scaleController);
  final deviceHandler = DevicesHandler(controller: deviceController);

  // Start server
  final server = await io.serve(
      _init(
        deviceHandler,
        de1Handler,
        scaleHandler,
      ),
      '0.0.0.0',
      8080);
  log.info('Web server running on ${server.address.host}:${server.port}');
}

Handler _init(
  DevicesHandler deviceHandler,
  De1Handler de1Handler,
  ScaleHandler scaleHandler,
) {
  log.info("called _init");
  var app = Router().plus;

  jsonContentTypeMiddleware(Handler innerHandler) {
    return (Request request) async {
      log.fine("handling request: ${request.requestedUri.path}");
      final response = await innerHandler(request);

      // Option 1: Check by path if it starts with "/ws" (or any other condition)
      if (request.requestedUri.path.startsWith('/ws')) {
        return response;
      }

      // Option 2: Alternatively, check if the request has an Upgrade header
      // if ((request.headers['upgrade']?.toLowerCase() ?? '') == 'websocket') {
      //   return response;
      // }

      // Add the header to responses that aren’t websocket-related.
      return response.change(headers: {
        ...response.headersAll,
        'content-type': 'application/json',
        if (kDebugMode) 'Access-Control-Allow-Origin': '*',
      });
    };
  }

  app.use(jsonContentTypeMiddleware);

  deviceHandler.addRoutes(app);
  de1Handler.addRoutes(app);
  scaleHandler.addRoutes(app);

  return app.call;
}
