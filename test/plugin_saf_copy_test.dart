import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/plugins_settings_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const safUtil = MethodChannel('saf_util');
  const safStream = MethodChannel('saf_stream');
  late Directory destination;

  setUp(() async {
    destination = await Directory.systemTemp.createTemp('plugin_saf_test');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(safUtil, (call) async {
          if (call.method != 'list') return null;
          final uri = (call.arguments as Map)['uri'];
          return switch (uri) {
            'content://plugin' => [
              {
                'uri': 'content://manifest',
                'name': 'manifest.json',
                'isDir': false,
              },
              {
                'uri': 'content://assets',
                'name': 'assets',
                'isDir': true,
              },
            ],
            'content://assets' => [
              {
                'uri': 'content://asset',
                'name': 'page.html',
                'isDir': false,
              },
            ],
            _ => [],
          };
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(safStream, (call) async {
          if (call.method != 'copyToLocalFile') return null;
          final arguments = call.arguments as Map;
          final contents = switch (arguments['src']) {
            'content://manifest' => '{}',
            'content://asset' => '<html></html>',
            _ => throw StateError('Unexpected source URI'),
          };
          await File(arguments['dest'] as String).writeAsString(contents);
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(safUtil, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(safStream, null);
    await destination.delete(recursive: true);
  });

  test('copies an Android SAF plugin directory recursively', () async {
    await copyPluginDirectoryFromSaf('content://plugin', destination);

    expect(
      await File('${destination.path}/manifest.json').readAsString(),
      '{}',
    );
    expect(
      await File('${destination.path}/assets/page.html').readAsString(),
      '<html></html>',
    );
  });
}
