part of '../webserver_service.dart';

/// REST API handler for log buffer export
class LogsHandler {
  final LogBuffer _logBuffer;

  LogsHandler({required LogBuffer logBuffer}) : _logBuffer = logBuffer;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/logs', _handleGetLogs);
  }

  /// GET /api/v1/logs
  /// Returns the current log buffer contents as plain text.
  /// Does not trigger telemetry upload - reads local buffer only.
  Future<Response> _handleGetLogs(Request request) async {
    final contents = _logBuffer.getContents();
    return Response.ok(
      contents,
      headers: {'content-type': 'text/plain'},
    );
  }
}
