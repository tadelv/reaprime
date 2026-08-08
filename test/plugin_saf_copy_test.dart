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
              {'uri': 'content://assets', 'name': 'assets', 'isDir': true},
            ],
            'content://assets' => [
              {'uri': 'content://asset', 'name': 'page.html', 'isDir': false},
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

  test('rejects a self-referencing SAF directory', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(safUtil, (call) async {
          if (call.method != 'list') return null;
          return [
            {'uri': 'content://cycle', 'name': 'cycle', 'isDir': true},
          ];
        });

    await expectLater(
      copyPluginDirectoryFromSaf('content://cycle', destination),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('repeated directory'),
        ),
      ),
    );
  });

  test('rejects excessive SAF directory nesting', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(safUtil, (call) async {
          if (call.method != 'list') return null;
          final uri = (call.arguments as Map)['uri'] as String;
          final depth = int.parse(uri.split('/').last);
          return [
            {
              'uri': 'content://depth/${depth + 1}',
              'name': 'nested',
              'isDir': true,
            },
          ];
        });

    await expectLater(
      copyPluginDirectoryFromSaf('content://depth/0', destination),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('maximum depth'),
        ),
      ),
    );
  });

  test('rejects excessive SAF directory entries', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(safUtil, (call) async {
          if (call.method != 'list') return null;
          return List.generate(
            10001,
            (index) => {
              'uri': 'content://file/$index',
              'name': '$index.txt',
              'isDir': false,
            },
          );
        });

    await expectLater(
      copyPluginDirectoryFromSaf('content://plugin', destination),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('too many entries'),
        ),
      ),
    );
  });
}
