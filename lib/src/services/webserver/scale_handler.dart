part of '../webserver_service.dart';

class ScaleHandler {
  final ScaleController _controller;

  final Logger _log = Logger("Scale handler");

  ScaleHandler({required ScaleController controller})
      : _controller = controller;

  addRoutes(RouterPlus app) {
    app.put('/api/v1/scale/<command>', (request, command) async {
      switch (command) {
        case 'tare':
          _log.fine("handling api tare command");
          await _controller.connectedScale().tare();
          return Response.ok('');
        default:
          return Response.notFound("");
      }
    });
    app.get('/ws/v1/scale/snapshot', sws.webSocketHandler(_handleSnapshot));
  }

  void _handleSnapshot(WebSocketChannel socket, String? _) async {
    log.fine("handling websocket connection");
    var scale = _controller.connectedScale();
    var sub = scale.currentSnapshot.listen((snapshot) {
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
  }
}
