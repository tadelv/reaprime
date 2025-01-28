import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart' as route;
import 'package:shelf_web_socket/shelf_web_socket.dart' as sWs;
import 'package:web_socket_channel/web_socket_channel.dart';

late De1Controller _controller;
final log = Logger("Webservice");

void startWebServer(De1Controller de1Controller) async {
  _controller = de1Controller;

  var router =
      (route.Router()
        ..get('/api/machine/state', _stateHandler)
        ..get('/ws/machine/snapshot', sWs.webSocketHandler(_handleSnapshot))
        ..post('/api/profile', _profileHandler));

  router.put('/api/machine/state/<state>', _requestStateHandler);
  router.post('/api/machine/shotSettings', _shotSettingsHandler);
  router.get(
    '/ws/machine/shotSettings',
    sWs.webSocketHandler(_handleShotSettings),
  );
  router.get(
    '/ws/machine/waterLevels',
    sWs.webSocketHandler(_handleWaterLevels),
  );

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  // Start server
  final server = await io.serve(handler, '0.0.0.0', 8080);
  log.info('Web server running on ${server.address.host}:${server.port}');
}

Future<Response> _stateHandler(Request request) async {
  try {
    var de1 = await _controller.connectedDe1();
    var snapshot = await de1.currentSnapshot.first;
    return Response.ok(
      jsonEncode({
        'state': snapshot.state.state.name,
        'substate': snapshot.state.substate.name,
      }),
    );
  } catch (e, st) {
    return Response.notFound(
      jsonEncode({'error': e.toString(), 'st': st.toString()}),
    );
  }
}

Future<Response> _requestStateHandler(Request request, String newState) async {
  try {
    var requestState = MachineState.values.byName(newState);
    var de1 = await _controller.connectedDe1();
    await de1.requestState(requestState);
    return Response.ok("");
  } catch (e, st) {
    return Response.badRequest(
      body: jsonEncode({'error': e.toString(), 'st': st.toString()}),
    );
  }
}

Future<Response> _profileHandler(Request request) async {
  try {
    final payload = await request.readAsString();

    Map<String, dynamic> json = jsonDecode(payload);
    Profile profile = Profile.fromJson(json);
    var de1 = await _controller.connectedDe1();
    await de1.setProfile(profile);
    return Response.ok("");
  } catch (e, st) {
    return Response.badRequest(
      body: jsonEncode({'error': e.toString(), 'st': st.toString()}),
    );
  }
}

Future<Response> _shotSettingsHandler(Request request) async {
  try {
    final payload = await request.readAsString();

    Map<String, dynamic> json = jsonDecode(payload);
    De1ShotSettings settings = De1ShotSettings.fromJson(json);
    var de1 = await _controller.connectedDe1();
    await de1.updateShotSettings(settings);
    return Response.ok("");
  } catch (e, st) {
    return Response.badRequest(
      body: jsonEncode({'error': e.toString(), 'st': st.toString()}),
    );
  }
}

_handleSnapshot(WebSocketChannel socket) async {
  log.fine("handling websocket connection");
  var de1 = await _controller.connectedDe1();
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
  log.finest("websocket closed");
}

_handleShotSettings(WebSocketChannel socket) async {
  log.fine('handling shot settings connection');
  var de1 = await _controller.connectedDe1();
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
}

_handleWaterLevels(WebSocketChannel socket) async {
  log.fine('handling water levels connection');
  var de1 = await _controller.connectedDe1();
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
}
