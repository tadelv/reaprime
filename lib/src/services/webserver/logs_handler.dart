part of '../webserver_service.dart';

/// REST API handler for log file access
///
/// GET /api/v1/logs?kb=N — returns last N kilobytes of the log file.
/// Without `kb`, returns the entire file.
class LogsHandler {
  final String _logFilePath;

  LogsHandler({required String logFilePath}) : _logFilePath = logFilePath;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/logs', _handleGetLogs);
  }

  Future<Response> _handleGetLogs(Request request) async {
    final file = File(_logFilePath);
    if (!await file.exists()) {
      return Response.notFound('Log file not found');
    }

    final kbParam = request.url.queryParameters['kb'];
    if (kbParam != null) {
      final kb = int.tryParse(kbParam);
      if (kb == null || kb <= 0) {
        return Response.badRequest(body: 'kb must be a positive integer');
      }
      final bytes = kb * 1024;
      final fileLength = await file.length();
      final start = fileLength > bytes ? fileLength - bytes : 0;
      final raf = await file.open();
      try {
        await raf.setPosition(start);
        final data = await raf.read(bytes);
        return Response.ok(
          String.fromCharCodes(data),
          headers: {'content-type': 'text/plain'},
        );
      } finally {
        await raf.close();
      }
    }

    final contents = await file.readAsString();
    return Response.ok(
      contents,
      headers: {'content-type': 'text/plain'},
    );
  }
}
