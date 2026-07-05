import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';

void main() {
  const token = 'abc.123';
  const script = '<script>window.__REA_PROXY_TOKEN__="abc.123";</script>';

  test('injects before </head> when present', () {
    final out = injectProxyTokenScript(
      '<html><head><title>x</title></head><body>hi</body></html>',
      token,
    );
    expect(out, contains('$script</head>'));
    expect(out.indexOf(script), lessThan(out.indexOf('<body>')));
  });

  test('injects before </body> when there is no head', () {
    final out = injectProxyTokenScript('<body>hi</body>', token);
    expect(out, '<body>hi$script</body>');
  });

  test('prepends when neither head nor body is present', () {
    final out = injectProxyTokenScript('just text', token);
    expect(out, '${script}just text');
  });

  test('returns html unchanged when token is null or empty', () {
    const html = '<html><head></head></html>';
    expect(injectProxyTokenScript(html, null), html);
    expect(injectProxyTokenScript(html, ''), html);
  });

  test('json-encodes the token (escapes quotes)', () {
    final out = injectProxyTokenScript('<head></head>', 'a"b');
    expect(out, contains(r'window.__REA_PROXY_TOKEN__="a\"b";'));
  });

  group('serveFolderAtPath offline', () {
    late Directory tempDir;
    late WebUIService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('webui_offline_test');
      // Minimal content — shelf_io.serve needs something to serve.
      await File(
        '${tempDir.path}/index.html',
      ).writeAsString('<html><body>test</body></html>');
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

    test('falls back to localhost when getWifiIP throws (gh#337)', () async {
      WebUIService.resolveWifiIP = () async => throw Exception('no wifi');

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

    test(
      'falls back to localhost when getWifiIP returns empty string',
      () async {
        WebUIService.resolveWifiIP = () async => '';

        await service.serveFolderAtPath(tempDir.path);

        expect(service.isServing, isTrue);
        expect(service.deviceIp(), 'localhost');
      },
    );
  });
}
