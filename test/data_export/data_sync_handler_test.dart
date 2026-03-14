import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export_handler.dart';
import 'package:reaprime/src/services/webserver/data_sync_handler.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// A simple mock section that stores/returns canned data.
class MockExportSection implements DataExportSection {
  @override
  final String filename;

  final dynamic exportData;
  final SectionImportResult importResult;

  /// Captured import calls for verification.
  dynamic lastImportedData;
  ConflictStrategy? lastStrategy;
  bool importCalled = false;

  MockExportSection({
    required this.filename,
    this.exportData = const {'mock': true},
    this.importResult = const SectionImportResult(imported: 1),
  });

  @override
  Future<dynamic> export() async => exportData;

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    importCalled = true;
    lastImportedData = data;
    lastStrategy = strategy;
    return importResult;
  }
}

List<int> buildZip(Map<String, dynamic> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, jsonEncode(entry.value)));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  late MockExportSection profileSection;

  setUp(() {
    profileSection = MockExportSection(
      filename: 'profiles.json',
      exportData: {'profiles': []},
      importResult: const SectionImportResult(imported: 1),
    );
  });

  Handler buildSyncHandler(http.Client client) {
    final exportHandler = DataExportHandler(
      sections: [profileSection],
    );
    final syncHandler = DataSyncHandler(
      exportHandler: exportHandler,
      httpClient: client,
    );
    final app = Router().plus;
    syncHandler.addRoutes(app);
    return app.call;
  }

  Future<Response> sendSync(Handler handler, Map<String, dynamic> body) async {
    return await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v1/data/sync'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  group('DataSyncHandler', () {
    group('validation', () {
      test('returns 400 when target is missing', () async {
        final client = http_testing.MockClient(
            (_) async => http.Response('', 200));
        final handler = buildSyncHandler(client);

        final response = await sendSync(handler, {'mode': 'pull'});

        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['message'], contains('target'));
      });

      test('returns 400 when mode is missing', () async {
        final client = http_testing.MockClient(
            (_) async => http.Response('', 200));
        final handler = buildSyncHandler(client);

        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
        });

        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['message'], contains('mode'));
      });

      test('returns 400 for invalid target URL', () async {
        final client = http_testing.MockClient(
            (_) async => http.Response('', 200));
        final handler = buildSyncHandler(client);

        final response = await sendSync(handler, {
          'target': 'not-a-url',
          'mode': 'pull',
        });

        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], 'Invalid target URL');
      });

      test('returns 400 for invalid mode', () async {
        final client = http_testing.MockClient(
            (_) async => http.Response('', 200));
        final handler = buildSyncHandler(client);

        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'invalid',
        });

        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], 'Invalid mode');
      });

      test('returns 400 for invalid onConflict value', () async {
        final client = http_testing.MockClient(
            (_) async => http.Response('', 200));
        final handler = buildSyncHandler(client);

        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'pull',
          'onConflict': 'merge',
        });

        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], 'Invalid onConflict value');
      });

      test('returns 400 for invalid JSON body', () async {
        final client = http_testing.MockClient(
            (_) async => http.Response('', 200));
        final exportHandler = DataExportHandler(sections: [profileSection]);
        final syncHandler = DataSyncHandler(
          exportHandler: exportHandler,
          httpClient: client,
        );
        final app = Router().plus;
        syncHandler.addRoutes(app);

        final response = await app.call(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/data/sync'),
            body: 'not json',
            headers: {'content-type': 'application/json'},
          ),
        );

        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], 'Invalid JSON');
      });
    });

    group('pull mode', () {
      test('pulls data from target and imports locally', () async {
        final targetZip = buildZip({
          'metadata.json': {'formatVersion': 1, 'platform': 'android'},
          'profiles.json': {'profiles': [
            {'id': 'remote1', 'name': 'Remote Profile'}
          ]},
        });

        final client = http_testing.MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'http://192.168.1.50:8080/api/v1/data/export',
          );
          return http.Response.bytes(targetZip, 200);
        });

        final handler = buildSyncHandler(client);
        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'pull',
        });

        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        expect(body['pull'], contains('profiles'));
        expect(profileSection.importCalled, isTrue);
      });

      test('pull uses skip strategy by default', () async {
        final targetZip = buildZip({
          'metadata.json': {'formatVersion': 1},
          'profiles.json': {'profiles': []},
        });

        final client = http_testing.MockClient(
            (_) async => http.Response.bytes(targetZip, 200));

        final handler = buildSyncHandler(client);
        await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'pull',
        });

        expect(profileSection.lastStrategy, ConflictStrategy.skip);
      });

      test('pull uses overwrite strategy when specified', () async {
        final targetZip = buildZip({
          'metadata.json': {'formatVersion': 1},
          'profiles.json': {'profiles': []},
        });

        final client = http_testing.MockClient(
            (_) async => http.Response.bytes(targetZip, 200));

        final handler = buildSyncHandler(client);
        await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'pull',
          'onConflict': 'overwrite',
        });

        expect(profileSection.lastStrategy, ConflictStrategy.overwrite);
      });

      test('pull returns 502 when target returns error', () async {
        final client = http_testing.MockClient(
            (_) async => http.Response('Server Error', 500));

        final handler = buildSyncHandler(client);
        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'pull',
        });

        expect(response.statusCode, 502);
        final body = jsonDecode(await response.readAsString());
        expect(body['pull']['error'], 'Target error');
        expect(body['pull']['status'], 500);
      });

      test('pull returns 502 when target is unreachable', () async {
        final client = http_testing.MockClient(
            (_) => throw http.ClientException('Connection refused'));

        final handler = buildSyncHandler(client);
        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'pull',
        });

        expect(response.statusCode, 502);
        final body = jsonDecode(await response.readAsString());
        expect(body['pull']['error'], 'Target unreachable');
      });
    });

    group('push mode', () {
      test('exports local data and sends to target', () async {
        Uri? capturedUri;
        List<int>? capturedBody;

        final client = http_testing.MockClient((request) async {
          capturedUri = request.url;
          capturedBody = request.bodyBytes;
          expect(request.method, 'POST');
          return http.Response(
            '{"profiles":{"imported":1,"skipped":0}}',
            200,
          );
        });

        final handler = buildSyncHandler(client);
        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'push',
          'onConflict': 'overwrite',
        });

        expect(response.statusCode, 200);
        expect(
          capturedUri.toString(),
          'http://192.168.1.50:8080/api/v1/data/import?onConflict=overwrite',
        );

        // Verify ZIP was sent
        final archive = ZipDecoder().decodeBytes(capturedBody!);
        expect(archive.findFile('profiles.json'), isNotNull);

        final body = jsonDecode(await response.readAsString());
        expect(body['push'], isNotNull);
      });

      test('push uses skip strategy by default', () async {
        Uri? capturedUri;

        final client = http_testing.MockClient((request) async {
          capturedUri = request.url;
          return http.Response('{"profiles":{"imported":0}}', 200);
        });

        final handler = buildSyncHandler(client);
        await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'push',
        });

        expect(capturedUri.toString(),
            contains('onConflict=skip'));
      });

      test('push returns 502 when target returns error', () async {
        final client = http_testing.MockClient(
            (_) async => http.Response('Server Error', 500));

        final handler = buildSyncHandler(client);
        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'push',
        });

        expect(response.statusCode, 502);
        final body = jsonDecode(await response.readAsString());
        expect(body['push']['error'], 'Target error');
        expect(body['push']['status'], 500);
      });

      test('push returns 502 when target is unreachable', () async {
        final client = http_testing.MockClient(
            (_) => throw http.ClientException('Connection refused'));

        final handler = buildSyncHandler(client);
        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'push',
        });

        expect(response.statusCode, 502);
        final body = jsonDecode(await response.readAsString());
        expect(body['push']['error'], 'Target unreachable');
      });
    });

    group('two_way mode', () {
      test('performs both pull and push', () async {
        final targetZip = buildZip({
          'metadata.json': {'formatVersion': 1},
          'profiles.json': {'profiles': []},
        });

        int requestCount = 0;
        final client = http_testing.MockClient((request) async {
          requestCount++;
          if (request.method == 'GET') {
            return http.Response.bytes(targetZip, 200);
          }
          return http.Response('{"profiles":{"imported":0}}', 200);
        });

        final handler = buildSyncHandler(client);
        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'two_way',
        });

        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        expect(body['pull'], isNotNull);
        expect(body['push'], isNotNull);
        expect(requestCount, 2);
      });

      test('returns 207 when pull succeeds but push fails', () async {
        final targetZip = buildZip({
          'metadata.json': {'formatVersion': 1},
          'profiles.json': {'profiles': []},
        });

        final client = http_testing.MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response.bytes(targetZip, 200);
          }
          return http.Response('Server Error', 500);
        });

        final handler = buildSyncHandler(client);
        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'two_way',
        });

        expect(response.statusCode, 207);
        final body = jsonDecode(await response.readAsString());
        expect(body['pull'], contains('profiles'));
        expect(body['push']['error'], 'Target error');
      });

      test('returns 207 when push succeeds but pull fails', () async {
        final client = http_testing.MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response('Server Error', 500);
          }
          return http.Response('{"profiles":{"imported":0}}', 200);
        });

        final handler = buildSyncHandler(client);
        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'two_way',
        });

        expect(response.statusCode, 207);
        final body = jsonDecode(await response.readAsString());
        expect(body['pull']['error'], 'Target error');
        expect(body['push'], isNotNull);
      });

      test('returns 502 when both pull and push fail', () async {
        final client = http_testing.MockClient(
            (_) async => http.Response('Server Error', 500));

        final handler = buildSyncHandler(client);
        final response = await sendSync(handler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'two_way',
        });

        expect(response.statusCode, 502);
      });
    });
  });
}
