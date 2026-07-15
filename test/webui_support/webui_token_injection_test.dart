import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';

void main() {
  const token = 'abc.123';
  const tokenAssignment = 'window.__REA_PROXY_TOKEN__="abc.123";';

  test('injects the skin API before </head> when present', () {
    final out = injectSkinApiScript(
      '<html><head><title>x</title></head><body>hi</body></html>',
      token,
    );
    expect(out, contains('window.decentApp'));
    expect(out, contains(tokenAssignment));
    expect(out.indexOf('<script>'), lessThan(out.indexOf('<body>')));
  });

  test('injects before </body> when there is no head', () {
    final out = injectSkinApiScript('<body>hi</body>', token);
    expect(out, startsWith('<body>hi<script>'));
    expect(out, endsWith('</script></body>'));
  });

  test('prepends when neither head nor body is present', () {
    final out = injectSkinApiScript('just text', token);
    expect(out, startsWith('<script>'));
    expect(out, endsWith('</script>just text'));
  });

  test('injects the skin API without a proxy token', () {
    const html = '<html><head></head></html>';
    for (final token in [null, '']) {
      final out = injectSkinApiScript(html, token);
      expect(out, contains('window.decentApp'));
      expect(out, isNot(contains('__REA_PROXY_TOKEN__')));
    }
  });

  test('json-encodes the token (escapes quotes)', () {
    final out = injectSkinApiScript('<head></head>', 'a"b');
    expect(out, contains(r'window.__REA_PROXY_TOKEN__="a\"b";'));
  });

  test('skin API exits only from the embedded host', () {
    final out = injectSkinApiScript('<head></head>', null);
    expect(out, contains('if(window.__DECENT_HOST__)'));
    expect(out, contains("window.location.href='decent://dashboard'"));
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

    test('serves the skin API on port 3000', () async {
      WebUIService.resolveWifiIP = () async => 'localhost';
      await service.serveFolderAtPath(tempDir.path);

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.getUrl(Uri.parse('http://localhost:3000/'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(body, contains('window.decentApp'));
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
