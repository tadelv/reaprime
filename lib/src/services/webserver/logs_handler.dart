part of '../webserver_service.dart';

/// REST API handler for log file access
///
/// GET /api/v1/logs?kb=N — returns last N kilobytes of the log file.
/// Without `kb`, returns the entire file.
///
/// Lines are served newest-first by default. Pass `order=asc` to get the
/// original on-disk chronological order (oldest first); `order=desc` is the
/// explicit form of the default.
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

    final order = _parseLogOrder(request);
    if (order == null) {
      return Response.badRequest(body: "order must be 'asc' or 'desc'");
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
          _orderLogLines(String.fromCharCodes(data), order),
          headers: {'content-type': 'text/plain'},
        );
      } finally {
        await raf.close();
      }
    }

    final contents = await file.readAsString();
    return Response.ok(
      _orderLogLines(contents, order),
      headers: {'content-type': 'text/plain'},
    );
  }
}

/// Output line order for the log endpoints.
enum _LogOrder {
  /// Original on-disk order: oldest entries first.
  ascending,

  /// Newest entries first (the default).
  descending,
}

/// Parse the optional `order` query parameter shared by the log endpoints.
///
/// Accepts `desc` (newest-first, the default when absent) or `asc`
/// (oldest-first, the original on-disk order), case-insensitive. Returns `null`
/// for an unrecognized value so the caller can reject it with `400`.
_LogOrder? _parseLogOrder(Request request) {
  final raw = request.url.queryParameters['order'];
  if (raw == null) return _LogOrder.descending;
  switch (raw.toLowerCase()) {
    case 'asc':
      return _LogOrder.ascending;
    case 'desc':
      return _LogOrder.descending;
    default:
      return null;
  }
}

/// Apply [order] to raw, chronological log [contents].
///
/// [_LogOrder.ascending] returns the text unchanged; [_LogOrder.descending]
/// reverses it to newest-first via [_reverseLogLines]. Shared by [LogsHandler]
/// and [WebViewLogsHandler], which are both `part of` the webserver library.
String _orderLogLines(String contents, _LogOrder order) {
  return order == _LogOrder.ascending ? contents : _reverseLogLines(contents);
}

/// Reverse the line order of [contents] so the newest log entries appear first.
///
/// Log files are written oldest-first; the REST log endpoints serve them
/// newest-first by default for readability.
///
/// Uses [LineSplitter] so `\n`, `\r\n`, and `\r` terminators are handled and a
/// trailing newline doesn't produce a leading blank line after reversal.
String _reverseLogLines(String contents) {
  final lines = const LineSplitter().convert(contents);
  if (lines.isEmpty) return contents;
  return '${lines.reversed.join('\n')}\n';
}
