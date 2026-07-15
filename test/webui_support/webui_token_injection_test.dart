import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';

void main() {
  const token = 'abc.123';
  const tokenAssignment = 'window.__REA_PROXY_TOKEN__="abc.123";';
  const scriptTag = '<script src="$skinApiScriptPath"></script>';

  test('handles mixed-case tags without moving the doctype', () {
    const html = '\uFEFF<!doctype html><HTML><HEAD></HEAD><BODY></BODY></HTML>';
    final out = injectSkinApiScriptTag(html);

    expect(out, startsWith('\uFEFF<!doctype html>'));
    expect(out, contains('<HEAD>$scriptTag</HEAD>'));
  });

  test('ignores closing-tag text inside scripts', () {
    const html = '''<!doctype html><html><head><script>
const headExample = "</head>";
const bodyExample = "</body>";
</script></head><body></body></html>''';
    final out = injectSkinApiScriptTag(html);

    expect(out, contains('const headExample = "</head>";'));
    expect(out, contains('const bodyExample = "</body>";'));
    expect(out, contains('</script>$scriptTag</head>'));
  });

  test('ignores markers inside comments and templates', () {
    const html =
        '<html><head><!-- </head> --><template></head></template></head>'
        '<body><!-- </body> --></body></html>';
    final out = injectSkinApiScriptTag(html);

    expect(out, contains('<!-- </head> -->'));
    expect(out, contains('<template></head></template>'));
    expect(out, contains('<!-- </body> -->$scriptTag</body>'));
  });

  test('inserts after a BOM and doctype when head and body are absent', () {
    const html = '\uFEFF<!doctype html>plain text';
    expect(
      injectSkinApiScriptTag(html),
      '\uFEFF<!doctype html>${scriptTag}plain text',
    );
  });

  test('injects into an empty document', () {
    expect(injectSkinApiScriptTag(''), scriptTag);
  });

  test('preserves UTF-8 BOM and declared response encodings', () {
    const html = '<html><head></head><body>caf\u00E9</body></html>';
    final utf8Bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(html)];
    final utf8Out = injectSkinApiScriptTagBytes(utf8Bytes, utf8);
    final latin1Out = injectSkinApiScriptTagBytes(latin1.encode(html), latin1);

    expect(utf8Out.take(3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(utf8Out).replaceFirst(scriptTag, ''), html);
    expect(latin1.decode(latin1Out).replaceFirst(scriptTag, ''), html);
  });

  test('builds the skin API without a proxy token', () {
    for (final token in [null, '']) {
      final script = buildSkinApiJavaScript(token);
      expect(script, contains('window.decentApp'));
      expect(script, isNot(contains('__REA_PROXY_TOKEN__')));
      expect(script, contains(skinExitDashboardUrl));
    }
  });

  test('json-encodes the token (escapes quotes)', () {
    final script = buildSkinApiJavaScript('a"b');
    expect(script, contains(r'window.__REA_PROXY_TOKEN__="a\"b";'));
  });

  group('serveFolderAtPath offline', () {
    late Directory tempDir;
    late WebUIService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('webui_offline_test');
      // Minimal content — shelf_io.serve needs something to serve.
      await File('${tempDir.path}/index.html')
          .writeAsString('<html><body>test</body></html>');
      service = WebUIService();
    });

    tearDown(() async {
      await service.stopServing();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      // Restore default behaviour so subsequent tests get real WiFi IP.
      WebUIService.resolveWifiIP = NetworkInfo().getWifiIP;
    });

    test('serves a CSP-compatible skin API on port 3000', () async {
      WebUIService.resolveWifiIP = () async => 'localhost';
      await File('${tempDir.path}/index.html').writeAsString(
        '<html><head><meta http-equiv="Content-Security-Policy" '
        'content="script-src \'self\'"></head><body>test</body></html>',
      );
      service.skinProxyToken = token;
      await service.serveFolderAtPath(tempDir.path);

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.getUrl(Uri.parse('http://localhost:3000/'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(body, contains(scriptTag));
      expect(body, contains("script-src 'self'"));
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), isNull);
      expect(response.headers.value(HttpHeaders.lastModifiedHeader), isNull);

      final scriptRequest = await client.getUrl(
        Uri.parse('http://localhost:3000$skinApiScriptPath'),
      );
      final scriptResponse = await scriptRequest.close();
      final script = await scriptResponse.transform(utf8.decoder).join();

      expect(scriptResponse.statusCode, HttpStatus.ok);
      expect(
        scriptResponse.headers.contentType?.mimeType,
        'application/javascript',
      );
      expect(script, contains('window.decentApp'));
      expect(script, contains(tokenAssignment));
    });

    test('falls back to localhost when getWifiIP throws (gh#337)', () async {
      WebUIService.resolveWifiIP = () async =>
          throw Exception('no wifi');

      await service.serveFolderAtPath(tempDir.path);

      expect(service.isServing, isTrue);
      expect(service.deviceIp(), 'localhost');
    });

    test('falls back to localhost when getWifiIP returns null', () async {
      WebUIService.resolveWifiIP = () async => null;

      await service.serveFolderAtPath(tempDir.path);

      expect(service.isServing, isTrue);
      expect(service.deviceIp(), 'localhost');
    });

    test('falls back to localhost when getWifiIP returns empty string',
        () async {
      WebUIService.resolveWifiIP = () async => '';

      await service.serveFolderAtPath(tempDir.path);

      expect(service.isServing, isTrue);
      expect(service.deviceIp(), 'localhost');
    });
  });
}
