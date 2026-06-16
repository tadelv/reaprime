import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reaprime/src/services/android_updater.dart';

void main() {
  group('AndroidUpdater.downloadUpdate streamed progress', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('updater_test');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    UpdateInfo info() => UpdateInfo(
          version: '1.2.3',
          downloadUrl: 'https://example.com/app.apk',
          releaseNotes: '',
          isPrerelease: false,
          tagName: 'v1.2.3',
        );

    test('reports monotonic progress ending at 1.0 and writes the file',
        () async {
      final chunks = <List<int>>[
        List.filled(40, 0),
        List.filled(40, 1),
        List.filled(20, 2),
      ];
      const total = 100;

      final client = MockClient.streaming((request, body) async {
        return http.StreamedResponse(
          Stream.fromIterable(chunks),
          200,
          contentLength: total,
        );
      });

      final updater = AndroidUpdater(
        owner: 'tadelv',
        repo: 'reaprime',
        httpClient: client,
      );

      final progress = <double>[];
      final path = await updater.downloadUpdate(
        info(),
        cacheDir: tmp,
        onProgress: progress.add,
      );

      expect(progress, isNotEmpty);
      expect(progress.last, closeTo(1.0, 1e-9));
      // monotonic non-decreasing
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }

      final file = File(path);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), total);
    });

    test('throws on non-200 response', () async {
      final client = MockClient.streaming((request, body) async {
        return http.StreamedResponse(const Stream.empty(), 404);
      });
      final updater = AndroidUpdater(
        owner: 'tadelv',
        repo: 'reaprime',
        httpClient: client,
      );

      expect(
        () => updater.downloadUpdate(info(), cacheDir: tmp),
        throwsA(isA<Exception>()),
      );
    });

    test('omits progress when Content-Length is unknown', () async {
      final client = MockClient.streaming((request, body) async {
        return http.StreamedResponse(
          Stream.fromIterable([List.filled(10, 0)]),
          200, // no contentLength
        );
      });
      final updater = AndroidUpdater(
        owner: 'tadelv',
        repo: 'reaprime',
        httpClient: client,
      );

      final progress = <double>[];
      await updater.downloadUpdate(info(), cacheDir: tmp,
          onProgress: progress.add);

      expect(progress, isEmpty);
    });
  });
}
