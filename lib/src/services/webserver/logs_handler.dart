part of '../webserver_service.dart';

/// REST API handler for log file access
///
/// GET /api/v1/logs?kb=N — returns last N kilobytes of the log file.
/// Without `kb`, returns the entire file.
///
/// Lines are served newest-first (reverse of the on-disk chronological order).
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
          _reverseLogLines(String.fromCharCodes(data)),
          headers: {'content-type': 'text/plain'},
        );
      } finally {
        await raf.close();
      }
    }

    final contents = await file.readAsString();
    return Response.ok(
      _reverseLogLines(contents),
      headers: {'content-type': 'text/plain'},
    );
  }
}

/// Reverse the line order of [contents] so the newest log entries appear first.
///
/// Log files are written oldest-first; the REST log endpoints serve them
/// newest-first for readability. Shared by [LogsHandler] and
/// [WebViewLogsHandler], which are both `part of` the webserver library.
///
/// Uses [LineSplitter] so `\n`, `\r\n`, and `\r` terminators are handled and a
/// trailing newline doesn't produce a leading blank line after reversal.
String _reverseLogLines(String contents) {
  final lines = const LineSplitter().convert(contents);
  if (lines.isEmpty) return contents;
  return '${lines.reversed.join('\n')}\n';
}
