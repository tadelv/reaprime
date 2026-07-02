part of '../webserver_service.dart';

/// REST API handler for log file access
///
/// GET /api/v1/logs?kb=N — returns last N kilobytes of the log file.
/// Without `kb`, returns the entire file.
///
/// Lines are served newest-first by default. Pass `order=asc` to get the
/// original on-disk chronological order (oldest first); `order=desc` is the
/// explicit form of the default.
///
/// Pass `rotated=1` to also include the rotated log files the appender leaves
/// behind (`log.txt.1`, `log.txt.2`, …). They are stitched into the response
/// in true chronological order — oldest rotation first, the live file last —
/// before `kb` windowing and `order` are applied.
class LogsHandler {
  final String _logFilePath;

  LogsHandler({required String logFilePath}) : _logFilePath = logFilePath;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/logs', _handleGetLogs);
  }

  Future<Response> _handleGetLogs(Request request) async {
    if (!await File(_logFilePath).exists()) {
      return Response.notFound('Log file not found');
    }

    final order = _parseLogOrder(request);
    if (order == null) {
      return Response.badRequest(body: "order must be 'asc' or 'desc'");
    }

    final rotated = _parseLogRotated(request);
    if (rotated == null) {
      return Response.badRequest(
        body: "rotated must be a boolean (1/0, true/false)",
      );
    }

    int? maxBytes;
    final kbParam = request.url.queryParameters['kb'];
    if (kbParam != null) {
      final kb = int.tryParse(kbParam);
      if (kb == null || kb <= 0) {
        return Response.badRequest(body: 'kb must be a positive integer');
      }
      maxBytes = kb * 1024;
    }

    final files = rotated ? _logFilesOldestToNewest() : [File(_logFilePath)];
    final contents = await _readChronological(files, maxBytes: maxBytes);
    return Response.ok(
      _orderLogLines(contents, order),
      headers: {'content-type': 'text/plain'},
    );
  }

  /// The live log file plus any rotated siblings, ordered oldest-first so their
  /// concatenation reads chronologically.
  ///
  /// Rotation naming mirrors `RotatingFileAppender`: rotation 0 is the base
  /// path (newest), higher numbers are progressively older (`log.txt.1`,
  /// `log.txt.2`, …). We probe upward until a rotation is missing, so the set
  /// stays in sync with whatever `keepRotateCount` the appender uses without
  /// this handler needing to know it.
  List<File> _logFilesOldestToNewest() {
    final rotated = <File>[];
    for (var i = 1; ; i++) {
      final file = File('$_logFilePath.$i');
      if (!file.existsSync()) break;
      rotated.add(file);
    }
    // Higher index = older, so oldest-first is the rotated files reversed,
    // with the live (newest) file last.
    return [...rotated.reversed, File(_logFilePath)];
  }

  /// Read [files] (assumed oldest-first) into one chronological string.
  ///
  /// When [maxBytes] is null the whole set is read. Otherwise only the most
  /// recent [maxBytes] bytes across the set are returned: files are read
  /// newest-first until the budget is filled, so older rotations that fall
  /// outside the window are never loaded. As with the single-file tail read,
  /// the byte cut can slice the oldest returned line mid-way.
  Future<String> _readChronological(List<File> files, {int? maxBytes}) async {
    if (maxBytes == null) {
      final buffer = StringBuffer();
      for (final file in files) {
        buffer.write(await file.readAsString());
      }
      return buffer.toString();
    }

    var remaining = maxBytes;
    final chunks = <String>[]; // newest-first; reversed before joining
    for (final file in files.reversed) {
      if (remaining <= 0) break;
      final length = await file.length();
      final start = length > remaining ? length - remaining : 0;
      final raf = await file.open();
      try {
        await raf.setPosition(start);
        final data = await raf.read(length - start);
        chunks.add(String.fromCharCodes(data));
      } finally {
        await raf.close();
      }
      remaining -= length - start;
    }
    return chunks.reversed.join();
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

/// Parse the optional `rotated` query parameter for `/api/v1/logs`.
///
/// Absent means `false` (live file only). Accepts `1`/`true`/`yes` and
/// `0`/`false`/`no`, case-insensitive. Returns `null` for an unrecognized
/// value so the caller can reject it with `400`.
bool? _parseLogRotated(Request request) {
  final raw = request.url.queryParameters['rotated'];
  if (raw == null) return false;
  switch (raw.toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
      return true;
    case '0':
    case 'false':
    case 'no':
      return false;
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
