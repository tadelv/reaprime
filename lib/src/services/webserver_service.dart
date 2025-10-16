import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/sensor_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/services/webserver/workflow_handler.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'dart:convert';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart' as sws;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';

part 'webserver/de1handler.dart';
part 'webserver/scale_handler.dart';
part 'webserver/devices_handler.dart';
part 'webserver/settings_handler.dart';
part 'webserver/sensors_handler.dart';

final log = Logger("Webservice");

Future<void> startWebServer(
  DeviceController deviceController,
  De1Controller de1Controller,
  ScaleController scaleController,
  SettingsController settingsController,
  SensorController sensorController,
  WorkflowController workflowController,
) async {
  log.info("starting webserver");
  final de1Handler = De1Handler(controller: de1Controller);
  final scaleHandler = ScaleHandler(controller: scaleController);
  final deviceHandler = DevicesHandler(controller: deviceController);
  final settingsHandler = SettingsHandler(controller: settingsController);
  final sensorsHandler = SensorsHandler(controller: sensorController);
  final workflowHandler = WorkflowHandler(
    controller: workflowController,
    de1controller: de1Controller,
  );
  // Start server
  final server = await io.serve(
    _init(
      deviceHandler,
      de1Handler,
      scaleHandler,
      settingsHandler,
      sensorsHandler,
      workflowHandler,
    ),
    '0.0.0.0',
    8080,
  );
  log.info('API Web server running on ${server.address.host}:${server.port}');

  // API Docs server
  // unpack api folder from assets to temp dir and serve
  await startApiDocsServer();
}

Handler _init(
  DevicesHandler deviceHandler,
  De1Handler de1Handler,
  ScaleHandler scaleHandler,
  SettingsHandler settingsHandler,
  SensorsHandler sensorsHandler,
  WorkflowHandler workflowHandler,
) {
  log.info("called _init");
  var app = Router().plus;

  Future<Response> Function(Request request) jsonContentTypeMiddleware(
    Handler innerHandler,
  ) {
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
      return response.change(
        headers: {...response.headersAll, 'content-type': 'application/json'},
      );
    };
  }

  app.use(jsonContentTypeMiddleware);

  deviceHandler.addRoutes(app);
  de1Handler.addRoutes(app);
  scaleHandler.addRoutes(app);
  settingsHandler.addRoutes(app);
  sensorsHandler.addRoutes(app);
  workflowHandler.addRoutes(app);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addMiddleware(jsonContentTypeMiddleware)
      .addHandler(app.call);

  return handler;
}

Future<void> startApiDocsServer() async {
  // Step 1: Create a temporary directory for the unpacked API docs
  final tempDir = await getTemporaryDirectory();
  final apiDir = Directory('${tempDir.path}/api');
  if (!apiDir.existsSync()) {
    apiDir.createSync(recursive: true);
  }

  // Step 2: List of files in assets/api/ you want to unpack.
  // Flutter doesn’t let you list asset directories dynamically,
  // so you must declare them explicitly in pubspec.yaml.
  // For example:
  // assets:
  //   - assets/api/index.html
  //   - assets/api/openapi.json
  //   - assets/api/style.css
  //
  // Then, manually list them here:
  final assetFiles = [
    'assets/api/index.html',
    'assets/api/rest_v1.yml',
    'assets/api/websocket_v1.yml',
  ];

  // Step 3: Copy each asset to the temp directory
  for (final assetPath in assetFiles) {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final filename = assetPath.split('/').last;
    final file = File('${apiDir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
  }

  // Step 4: Create a static file handler for the unpacked API docs
  final apiHandler = createStaticHandler(
    apiDir.path,
    defaultDocument: 'index.html',
    listDirectories: true,
  );

  // Step 5: Serve the handler on port 4001
  final apiServer = await io.serve(apiHandler, '0.0.0.0', 4001);
  log.info(
    '✅ API Docs server running at http://${apiServer.address.host}:${apiServer.port}',
  );
}
