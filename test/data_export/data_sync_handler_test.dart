import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export_handler.dart';
import 'package:reaprime/src/services/webserver/data_sync_handler.dart';
import 'package:shelf_plus/shelf_plus.dart';

class MockExportSection implements DataExportSection {
  @override
  final String filename;

  final dynamic exportData;
  final SectionImportResult importResult;
  ConflictStrategy? lastStrategy;

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
  final sections = [
    MockExportSection(filename: 'profiles.json', exportData: {'profiles': []}),
    MockExportSection(filename: 'shots.json', exportData: {'shots': []}),
  ];

  Handler buildSyncHandler(
    http.Client client, {
    List<DataExportSection>? registeredSections,
  }) {
    final exportHandler = DataExportHandler(
      sections: registeredSections ?? sections,
    );
    final syncHandler = DataSyncHandler(
      exportHandler: exportHandler,
      httpClient: client,
    );
    final app = Router().plus;
    syncHandler.addRoutes(app);
    return app.call;
  }

  Future<Response> sendSync(Handler handler, Map<String, dynamic> body) async =>
      await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/data/sync'),
          body: jsonEncode(body),
          headers: {'content-type': 'application/json'},
        ),
      );

  Map<String, dynamic> requestBody({
    required String mode,
    List<String>? selectedSections,
    bool? continueOnPullFailure,
    String? onConflict,
  }) => {
    'target': 'http://192.168.1.50:8080',
    'mode': mode,
    ...?selectedSections == null ? null : {'sections': selectedSections},
    ...?continueOnPullFailure == null
        ? null
        : {'continueOnPullFailure': continueOnPullFailure},
    ...?onConflict == null ? null : {'onConflict': onConflict},
  };

  group('DataSyncHandler', () {
    group('validation', () {
      test('requires sections for pull and two_way', () async {
        final handler = buildSyncHandler(
          http_testing.MockClient((_) async => http.Response('', 200)),
        );

        for (final mode in ['pull', 'two_way']) {
          final response = await sendSync(handler, requestBody(mode: mode));
          final body = jsonDecode(await response.readAsString());
          expect(response.statusCode, 400);
          expect(body['message'], contains('sections'));
        }
      });

      test('rejects an explicitly empty section list', () async {
        final handler = buildSyncHandler(
          http_testing.MockClient((_) async => http.Response('', 200)),
        );
        for (final mode in ['pull', 'two_way']) {
          final response = await sendSync(
            handler,
            requestBody(mode: mode, selectedSections: []),
          );
          final body = jsonDecode(await response.readAsString());
          expect(response.statusCode, 400);
          expect(body['message'], contains('sections'));
        }
      });

      test('deduplicates sections and rejects unknown names', () async {
        final handler = buildSyncHandler(
          http_testing.MockClient((_) async => http.Response('', 200)),
        );

        final unknownResponse = await sendSync(
          handler,
          requestBody(mode: 'push', selectedSections: ['unknown']),
        );
        expect(unknownResponse.statusCode, 400);

        final duplicateResponse = await sendSync(
          handler,
          requestBody(
            mode: 'pull',
            selectedSections: ['shots', 'shots', 'profiles'],
          ),
        );
        expect(duplicateResponse.statusCode, 502);
      });

      test('validates continueOnPullFailure and its mode', () async {
        final handler = buildSyncHandler(
          http_testing.MockClient((_) async => http.Response('', 200)),
        );

        final invalidType = await sendSync(
          handler,
          requestBody(mode: 'two_way', selectedSections: ['profiles'])
            ..['continueOnPullFailure'] = 'yes',
        );
        expect(invalidType.statusCode, 400);

        for (final mode in ['pull', 'push']) {
          final invalidMode = await sendSync(
            handler,
            requestBody(
              mode: mode,
              selectedSections: ['profiles'],
              continueOnPullFailure: true,
            ),
          );
          expect(invalidMode.statusCode, 400);
        }
      });

      test('allows push without sections', () async {
        final client = http_testing.MockClient(
          (_) async => http.Response(
            '{"profiles":{"imported":1},"shots":{"imported":1}}',
            200,
          ),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'push'),
        );
        expect(response.statusCode, 200);
      });
    });

    group('push mode', () {
      test('classifies legacy 200 errors semantically', () async {
        final client = http_testing.MockClient(
          (_) async => http.Response(
            '{"profiles":{"imported":2,"skipped":0},"shots":{"imported":0,"errors":["Failed to import shot records"]}}',
            200,
          ),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'push', selectedSections: ['profiles', 'shots']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 502);
        expect(body['status'], 'partial');
        expect(body['complete'], false);
        expect(body['partial'], true);
        expect(body['push']['profiles']['status'], 'complete');
        expect(body['push']['shots']['status'], 'failed');
        expect(
          body['push']['shots']['errors'],
          contains('Failed to import shot records'),
        );
        expect(body['phases']['push']['status'], 'partial');
      });

      test(
        'preserves declared failed status in a flat remote result',
        () async {
          final client = http_testing.MockClient(
            (_) async => http.Response(
              '{"profiles":{"status":"failed","imported":4}}',
              200,
            ),
          );
          final response = await sendSync(
            buildSyncHandler(client),
            requestBody(mode: 'push', selectedSections: ['profiles']),
          );
          final body = jsonDecode(await response.readAsString());

          expect(response.statusCode, 502);
          expect(body['status'], 'partial');
          expect(body['push']['profiles']['status'], 'failed');
          expect(body['phases']['push']['status'], 'partial');
        },
      );

      test('keeps remote 207 partial for single-direction push', () async {
        final client = http_testing.MockClient(
          (_) async => http.Response(
            '{"status":"partial","sections":{"profiles":{"imported":2},"shots":{"errors":["bad row"]}}}',
            207,
          ),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'push', selectedSections: ['profiles', 'shots']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 502);
        expect(body['status'], 'partial');
        expect(body['phases']['push']['status'], 'partial');
        expect(body['push']['profiles']['imported'], 2);
        expect(body['push']['shots']['errors'], contains('bad row'));
      });

      test('honors a structured remote failed phase', () async {
        final client = http_testing.MockClient(
          (_) async => http.Response(
            '{"status":"failed","complete":false,"error":"Import commit failed","message":"The target rejected the import.","sections":{"profiles":{"status":"complete","imported":2}}}',
            200,
          ),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'push', selectedSections: ['profiles']),
        );
        final body = jsonDecode(await response.readAsString());

        expect(response.statusCode, 502);
        expect(body['status'], 'failed');
        expect(body['push']['profiles']['status'], 'complete');
        expect(body['phases']['push']['status'], 'failed');
        expect(body['phases']['push']['error'], 'Import commit failed');
        expect(
          body['phases']['push']['message'],
          'The target rejected the import.',
        );
      });

      test('honors a structured remote partial phase', () async {
        final client = http_testing.MockClient(
          (_) async => http.Response(
            '{"status":"partial","complete":false,"partial":true,"sections":{"profiles":{"status":"complete","imported":2}}}',
            200,
          ),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'push', selectedSections: ['profiles']),
        );
        final body = jsonDecode(await response.readAsString());

        expect(response.statusCode, 502);
        expect(body['status'], 'partial');
        expect(body['phases']['push']['status'], 'partial');
      });

      test('warnings and conflict skips remain complete', () async {
        final client = http_testing.MockClient(
          (_) async => http.Response(
            '{"profiles":{"imported":0,"skipped":4,"warnings":["Existing profiles were retained"]},"shots":{"imported":0,"skipped":0}}',
            200,
          ),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'push', selectedSections: ['profiles', 'shots']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 200);
        expect(body['status'], 'complete');
        expect(body['push']['profiles']['status'], 'complete');
        expect(body['push']['profiles']['skipped'], 4);
        expect(body['push']['profiles']['warnings'], isNotEmpty);
        expect(body['phases']['push']['complete'], true);
      });

      test('synthesizes missing remote sections', () async {
        final client = http_testing.MockClient(
          (_) async => http.Response('{"profiles":{"imported":1}}', 200),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'push', selectedSections: ['profiles', 'shots']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 502);
        expect(body['push']['shots']['status'], 'failed');
        expect(body['push']['shots']['errors'].single, contains('Missing'));
        expect(body['phases']['push']['status'], 'partial');
      });

      test('rejects empty and malformed remote semantic results', () async {
        for (final remoteBody in [
          '{}',
          '[]',
          'not json',
          '{"profiles":{}}',
          '{"profiles":{"status":"invalid","imported":1}}',
          '{"sections":{"profiles":{"status":"failed"}}}',
        ]) {
          final client = http_testing.MockClient(
            (_) async => http.Response(remoteBody, 200),
          );
          final response = await sendSync(
            buildSyncHandler(client),
            requestBody(mode: 'push', selectedSections: ['profiles']),
          );
          final body = jsonDecode(await response.readAsString());
          expect(response.statusCode, 502);
          expect(body['phases']['push']['status'], 'failed');
        }
      });
    });

    group('pull mode', () {
      test(
        'classifies local section errors and preserves direct paths',
        () async {
          final client = http_testing.MockClient(
            (_) async => http.Response.bytes(
              buildZip({'profiles.json': {}, 'shots.json': {}}),
              200,
            ),
          );
          final handler = buildSyncHandler(
            client,
            registeredSections: [
              MockExportSection(
                filename: 'profiles.json',
                importResult: const SectionImportResult(imported: 2),
              ),
              MockExportSection(
                filename: 'shots.json',
                importResult: const SectionImportResult(
                  errors: ['Failed to import shots'],
                ),
              ),
            ],
          );
          final response = await sendSync(
            handler,
            requestBody(mode: 'pull', selectedSections: ['profiles', 'shots']),
          );
          final body = jsonDecode(await response.readAsString());
          expect(response.statusCode, 502);
          expect(body['pull']['profiles']['status'], 'complete');
          expect(body['pull']['shots']['status'], 'failed');
          expect(body['phases']['pull']['status'], 'partial');
        },
      );

      test('requires every requested archive section', () async {
        final client = http_testing.MockClient(
          (_) async =>
              http.Response.bytes(buildZip({'profiles.json': {}}), 200),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'pull', selectedSections: ['profiles', 'shots']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 502);
        expect(body['pull']['shots']['status'], 'failed');
        expect(body['pull']['shots']['errors'].single, contains('Missing'));
        expect(body['phases']['pull']['status'], 'partial');
      });

      test('returns a failed phase when the target has no sections', () async {
        final client = http_testing.MockClient(
          (_) async => http.Response.bytes(buildZip({}), 200),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'pull', selectedSections: ['profiles']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 502);
        expect(body['status'], 'failed');
        expect(body['phases']['pull']['status'], 'failed');
      });

      test('returns complete only when all sections import cleanly', () async {
        final client = http_testing.MockClient(
          (_) async => http.Response.bytes(
            buildZip({'profiles.json': {}, 'shots.json': {}}),
            200,
          ),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'pull', selectedSections: ['profiles', 'shots']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 200);
        expect(body['status'], 'complete');
        expect(body['complete'], true);
        expect(body['partial'], false);
        expect(body['phases']['pull']['status'], 'complete');
      });
    });

    group('two_way mode', () {
      test('runs push after a complete pull', () async {
        final targetZip = buildZip({'profiles.json': {}, 'shots.json': {}});
        var requestCount = 0;
        final client = http_testing.MockClient((request) async {
          requestCount++;
          if (request.method == 'GET') {
            return http.Response.bytes(targetZip, 200);
          }
          return http.Response(
            '{"profiles":{"imported":1},"shots":{"imported":1}}',
            200,
          );
        });
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'two_way', selectedSections: ['profiles', 'shots']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 200);
        expect(requestCount, 2);
        expect(body['status'], 'complete');
        expect(body['mode'], 'two_way');
        expect(body['phases']['pull']['status'], 'complete');
        expect(body['phases']['push']['status'], 'complete');
      });

      test('skips push after a fatal pull by default', () async {
        var postCount = 0;
        final client = http_testing.MockClient((request) async {
          if (request.method == 'POST') postCount++;
          return http.Response('Target unavailable', 500);
        });
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'two_way', selectedSections: ['profiles']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 502);
        expect(postCount, 0);
        expect(body['status'], 'failed');
        expect(body['push'], isEmpty);
        expect(body['phases']['pull']['status'], 'failed');
        expect(body['phases']['push']['status'], 'skipped');
        expect(body['phases']['push']['reason'], 'pull_not_complete');
      });

      test('skips push after a partial pull by default', () async {
        var postCount = 0;
        final client = http_testing.MockClient((request) async {
          if (request.method == 'POST') {
            postCount++;
            return http.Response('{}', 200);
          }
          return http.Response.bytes(buildZip({'profiles.json': {}}), 200);
        });
        final handler = buildSyncHandler(
          client,
          registeredSections: [
            MockExportSection(
              filename: 'profiles.json',
              importResult: const SectionImportResult(
                imported: 1,
                errors: ['bad row'],
              ),
            ),
          ],
        );
        final response = await sendSync(
          handler,
          requestBody(mode: 'two_way', selectedSections: ['profiles']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 207);
        expect(postCount, 0);
        expect(body['status'], 'partial');
        expect(body['phases']['push']['status'], 'skipped');
      });

      test('allows explicit continuation after a failed pull', () async {
        var postCount = 0;
        final client = http_testing.MockClient((request) async {
          if (request.method == 'GET') return http.Response('failed', 500);
          postCount++;
          return http.Response('{"profiles":{"imported":1}}', 200);
        });
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(
            mode: 'two_way',
            selectedSections: ['profiles'],
            continueOnPullFailure: true,
          ),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 207);
        expect(postCount, 1);
        expect(body['status'], 'partial');
        expect(body['phases']['pull']['status'], 'failed');
        expect(body['phases']['push']['status'], 'complete');
      });

      test('allows explicit continuation after a partial pull', () async {
        var postCount = 0;
        final client = http_testing.MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response.bytes(buildZip({'profiles.json': {}}), 200);
          }
          postCount++;
          return http.Response('{"profiles":{"imported":1}}', 200);
        });
        final handler = buildSyncHandler(
          client,
          registeredSections: [
            MockExportSection(
              filename: 'profiles.json',
              importResult: const SectionImportResult(
                imported: 1,
                errors: ['bad row'],
              ),
            ),
          ],
        );
        final response = await sendSync(
          handler,
          requestBody(
            mode: 'two_way',
            selectedSections: ['profiles'],
            continueOnPullFailure: true,
          ),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 207);
        expect(postCount, 1);
        expect(body['phases']['pull']['status'], 'partial');
        expect(body['phases']['push']['status'], 'complete');
      });

      test('returns 207 when pull completes and push is partial', () async {
        final client = http_testing.MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response.bytes(
              buildZip({'profiles.json': {}, 'shots.json': {}}),
              200,
            );
          }
          return http.Response(
            '{"profiles":{"imported":1},"shots":{"errors":["bad row"]}}',
            200,
          );
        });
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(mode: 'two_way', selectedSections: ['profiles', 'shots']),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 207);
        expect(body['status'], 'partial');
        expect(body['phases']['push']['status'], 'partial');
      });

      test('returns 502 when both explicitly continued phases fail', () async {
        final client = http_testing.MockClient(
          (_) async => http.Response('failed', 500),
        );
        final response = await sendSync(
          buildSyncHandler(client),
          requestBody(
            mode: 'two_way',
            selectedSections: ['profiles'],
            continueOnPullFailure: true,
          ),
        );
        final body = jsonDecode(await response.readAsString());
        expect(response.statusCode, 502);
        expect(body['status'], 'failed');
        expect(body['phases']['pull']['status'], 'failed');
        expect(body['phases']['push']['status'], 'failed');
      });
    });
  });
}
