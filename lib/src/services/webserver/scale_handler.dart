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
          try {
            await _controller.connectedScale().tare();
          } catch (e) {
            return jsonError({'error': e.toString()});
          }
          return Response.ok('');
        default:
          return Response.notFound("");
      }
    });
    app.put('/api/v1/scale/timer/<command>', (request, command) async {
      try {
        final scale = _controller.connectedScale();
        switch (command) {
          case 'start':
            _log.fine("handling api timer start command");
            await scale.startTimer();
            return Response.ok('');
          case 'stop':
            _log.fine("handling api timer stop command");
            await scale.stopTimer();
            return Response.ok('');
          case 'reset':
            _log.fine("handling api timer reset command");
            await scale.resetTimer();
            return Response.ok('');
          default:
            return Response.notFound("");
        }
      } catch (e) {
        return jsonError({'error': e.toString()});
      }
    });
    app.get('/ws/v1/scale/snapshot', sws.webSocketHandler(_handleSnapshot));
  }

  _handleSnapshot(WebSocketChannel socket, String? protocol) async {
    _log.fine("handling websocket connection");
    Scale scale;
    try {
      scale = _controller.connectedScale();
    } catch (e) {
      socket.sink.add(jsonEncode({'error': 'No scale connected'}));
      socket.sink.close();
      return;
    }
    var sub = scale.currentSnapshot.listen((snapshot) {
      try {
        var json = jsonEncode(snapshot.toJson());
        socket.sink.add(json);
      } catch (e, st) {
        _log.severe("failed to send: ", e, st);
      }
    });
    socket.stream.listen(
      (e) {},
      onDone: () => sub.cancel(),
      onError: (e, st) => sub.cancel(),
    );
  }
}
