import 'package:logging/logging.dart';
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

final log = Logger("Webservice");

Future<void> startWebServer(
  De1Controller de1Controller,
  ScaleController scaleController,
) async {
  log.info("starting webserver");
  final de1Handler = De1Handler(controller: de1Controller);
  final scaleHandler = ScaleHandler(controller: scaleController);

  // Start server
  final server = await io.serve(
      _init(
        de1Handler,
        scaleHandler,
      ),
      '0.0.0.0',
      8080);
  log.info('Web server running on ${server.address.host}:${server.port}');
}

Handler _init(
  De1Handler de1Handler,
  ScaleHandler scaleHandler,
) {
  log.info("called _init");
  var app = Router().plus;
  app.use(typeByExtension('json'));

  de1Handler.addRoutes(app);
  scaleHandler.addRoutes(app);

  return app.call;
}
