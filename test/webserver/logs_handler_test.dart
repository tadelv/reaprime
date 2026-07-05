import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:reaprime/src/services/webview_log_service.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// Stub that returns fixed contents, bypassing the IOSink-buffered file the
/// real [WebViewLogService] writes to (which would race a synchronous read).
class _StubWebViewLogService extends WebViewLogService {
  final String _contents;
  _StubWebViewLogService(this._contents) : super(logDirectoryPath: '/unused');

  @override
  String getContents() => _contents;
}

void main() {
  Future<Response> get(Handler handler, String path) async {
    return await handler(Request('GET', Uri.parse('http://localhost$path')));
  }

  group('LogsHandler GET /api/v1/logs', () {
    late Directory tmpDir;
    late File logFile;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('logs_handler_test');
      logFile = File('${tmpDir.path}/log.txt');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    Handler handlerFor(String path) {
      final app = Router().plus;
      LogsHandler(logFilePath: path).addRoutes(app);
      return app.call;
    }

    test('returns the whole file with lines newest-first', () async {
      // Written oldest-first, as the app writes them.
      const lines = ['oldest', 'middle', 'newest'];
      logFile.writeAsStringSync('${lines.join('\n')}\n');

      final res = await get(handlerFor(logFile.path), '/api/v1/logs');

      expect(res.statusCode, 200);
      expect(res.headers['content-type'], 'text/plain');
      expect(await res.readAsString(), 'newest\nmiddle\noldest\n');
    });

    test(
      'does not produce a leading blank line from a trailing newline',
      () async {
        logFile.writeAsStringSync('a\nb\nc\n');
        final res = await get(handlerFor(logFile.path), '/api/v1/logs');
        final body = await res.readAsString();
        expect(body, 'c\nb\na\n');
        expect(body.startsWith('\n'), isFalse);
      },
    );

    test('empty file yields an empty body (not a blank line)', () async {
      logFile.writeAsStringSync('');
      final res = await get(handlerFor(logFile.path), '/api/v1/logs');
      expect(res.statusCode, 200);
      expect(await res.readAsString(), '');
    });

    test('missing file returns 404', () async {
      final res = await get(
        handlerFor('${tmpDir.path}/nope.txt'),
        '/api/v1/logs',
      );
      expect(res.statusCode, 404);
    });

    test('?kb=N returns the most recent window, newest-first', () async {
      // 200 lines of 9 bytes each ("lineNNNN\n") = 1800 bytes, so a 1KB
      // window drops the oldest lines.
      final lines = [
        for (var i = 0; i < 200; i++) 'line${i.toString().padLeft(4, '0')}',
      ];
      logFile.writeAsStringSync('${lines.join('\n')}\n');

      final res = await get(handlerFor(logFile.path), '/api/v1/logs?kb=1');
      final body = await res.readAsString();

      expect(res.statusCode, 200);
      // Newest line first.
      expect(body.startsWith('line0199'), isTrue);
      // Oldest line dropped by the 1KB window.
      expect(body.contains('line0000'), isFalse);
      // A recent line is present, and ordering is descending.
      expect(body.contains('line0150'), isTrue);
      expect(body.indexOf('line0199'), lessThan(body.indexOf('line0150')));
    });

    test('?kb=0 is rejected', () async {
      logFile.writeAsStringSync('x\n');
      final res = await get(handlerFor(logFile.path), '/api/v1/logs?kb=0');
      expect(res.statusCode, 400);
    });

    test('?order=asc returns the original chronological order', () async {
      logFile.writeAsStringSync('oldest\nmiddle\nnewest\n');
      final res = await get(handlerFor(logFile.path), '/api/v1/logs?order=asc');
      expect(res.statusCode, 200);
      expect(await res.readAsString(), 'oldest\nmiddle\nnewest\n');
    });

    test('?order=desc is the explicit default (newest-first)', () async {
      logFile.writeAsStringSync('oldest\nmiddle\nnewest\n');
      final res = await get(
        handlerFor(logFile.path),
        '/api/v1/logs?order=desc',
      );
      expect(res.statusCode, 200);
      expect(await res.readAsString(), 'newest\nmiddle\noldest\n');
    });

    test('?order is case-insensitive', () async {
      logFile.writeAsStringSync('oldest\nnewest\n');
      final res = await get(handlerFor(logFile.path), '/api/v1/logs?order=ASC');
      expect(res.statusCode, 200);
      expect(await res.readAsString(), 'oldest\nnewest\n');
    });

    test('an unrecognized ?order value is rejected', () async {
      logFile.writeAsStringSync('x\n');
      final res = await get(
        handlerFor(logFile.path),
        '/api/v1/logs?order=sideways',
      );
      expect(res.statusCode, 400);
    });

    test('?kb=N&order=asc returns the window in chronological order', () async {
      final lines = [
        for (var i = 0; i < 200; i++) 'line${i.toString().padLeft(4, '0')}',
      ];
      logFile.writeAsStringSync('${lines.join('\n')}\n');

      final res = await get(
        handlerFor(logFile.path),
        '/api/v1/logs?kb=1&order=asc',
      );
      final body = await res.readAsString();

      expect(res.statusCode, 200);
      // Newest line last (chronological), oldest dropped by the 1KB window.
      expect(body.endsWith('line0199\n'), isTrue);
      expect(body.contains('line0000'), isFalse);
      expect(body.contains('line0150'), isTrue);
      expect(body.indexOf('line0150'), lessThan(body.indexOf('line0199')));
    });
  });

  group('WebViewLogsHandler GET /api/v1/webview/logs', () {
    Handler handlerFor(WebViewLogService service) {
      final app = Router().plus;
      WebViewLogsHandler(webViewLogService: service).addRoutes(app);
      return app.call;
    }

    test('returns console entries newest-first', () async {
      final service = _StubWebViewLogService(
        '[t1] [skin] [INFO] one\n'
        '[t2] [skin] [INFO] two\n'
        '[t3] [skin] [WARN] three\n',
      );

      final res = await get(handlerFor(service), '/api/v1/webview/logs');

      expect(res.statusCode, 200);
      expect(res.headers['content-type'], 'text/plain');
      expect(
        await res.readAsString(),
        '[t3] [skin] [WARN] three\n'
        '[t2] [skin] [INFO] two\n'
        '[t1] [skin] [INFO] one\n',
      );
    });

    test('empty log yields an empty body', () async {
      final res = await get(
        handlerFor(_StubWebViewLogService('')),
        '/api/v1/webview/logs',
      );
      expect(res.statusCode, 200);
      expect(await res.readAsString(), '');
    });

    test('?order=asc returns the original chronological order', () async {
      final service = _StubWebViewLogService(
        '[t1] [skin] [INFO] one\n'
        '[t2] [skin] [INFO] two\n'
        '[t3] [skin] [WARN] three\n',
      );

      final res = await get(
        handlerFor(service),
        '/api/v1/webview/logs?order=asc',
      );

      expect(res.statusCode, 200);
      expect(
        await res.readAsString(),
        '[t1] [skin] [INFO] one\n'
        '[t2] [skin] [INFO] two\n'
        '[t3] [skin] [WARN] three\n',
      );
    });

    test('an unrecognized ?order value is rejected', () async {
      final res = await get(
        handlerFor(_StubWebViewLogService('x\n')),
        '/api/v1/webview/logs?order=sideways',
      );
      expect(res.statusCode, 400);
    });
  });
}
