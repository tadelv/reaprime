import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export_handler.dart';
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

/// A section that throws on export.
class FailingExportSection implements DataExportSection {
  @override
  final String filename;

  FailingExportSection({required this.filename});

  @override
  Future<dynamic> export() async => throw Exception('Export failed');

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async => throw Exception('Import failed');
}

void main() {
  late DataExportHandler handler;
  late MockExportSection profileSection;
  late MockExportSection shotsSection;
  late Handler httpHandler;

  setUp(() {
    profileSection = MockExportSection(
      filename: 'profiles.json',
      exportData: {
        'profiles': [
          {'id': 'p1', 'name': 'Default'},
        ],
      },
      importResult: const SectionImportResult(
        imported: 1,
        skipped: 0,
        warnings: [],
      ),
    );

    shotsSection = MockExportSection(
      filename: 'shots.json',
      exportData: {
        'shots': [
          {'id': 's1', 'timestamp': '2024-01-01'},
        ],
      },
      importResult: const SectionImportResult(
        imported: 2,
        skipped: 1,
        warnings: [],
      ),
    );

    handler = DataExportHandler(sections: [profileSection, shotsSection]);

    final app = Router().plus;
    handler.addRoutes(app);
    httpHandler = app.call;
  });

  Future<Response> sendGet(String path) async {
    return await httpHandler(
      Request('GET', Uri.parse('http://localhost$path')),
    );
  }

  Future<Response> sendPost(String path, {required List<int> body}) async {
    return await httpHandler(
      Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body: body,
        headers: {'content-type': 'application/octet-stream'},
      ),
    );
  }

  /// Helper: build a ZIP archive with given files and return its bytes.
  List<int> buildZip(Map<String, dynamic> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      final jsonStr = jsonEncode(entry.value);
      archive.addFile(ArchiveFile.string(entry.key, jsonStr));
    }
    return ZipEncoder().encode(archive);
  }

  List<int> buildZipEntries(Map<String, String> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile.string(entry.key, entry.value));
    }
    return ZipEncoder().encode(archive);
  }

  group('DataExportHandler', () {
    group('GET /api/v1/data/export', () {
      test(
        'returns ZIP with correct content-type and Content-Disposition',
        () async {
          final response = await sendGet('/api/v1/data/export');

          expect(response.statusCode, 200);
          expect(response.headers['content-type'], 'application/zip');
          expect(
            response.headers['content-disposition'],
            startsWith('attachment; filename="decent_export_'),
          );
          expect(response.headers['content-disposition'], endsWith('.zip"'));
        },
      );

      test('ZIP contains metadata.json with correct fields', () async {
        final response = await sendGet('/api/v1/data/export');
        final bytes = await response.read().expand((b) => b).toList();
        final archive = ZipDecoder().decodeBytes(bytes);

        final metadataFile = archive.findFile('metadata.json');
        expect(metadataFile, isNotNull);

        final metadata =
            jsonDecode(utf8.decode(metadataFile!.content))
                as Map<String, dynamic>;
        expect(metadata['formatVersion'], 1);
        expect(metadata.containsKey('appVersion'), isTrue);
        expect(metadata.containsKey('commitSha'), isTrue);
        expect(metadata.containsKey('branch'), isTrue);
        expect(metadata.containsKey('exportTimestamp'), isTrue);
        expect(metadata.containsKey('platform'), isTrue);
      });

      test('ZIP contains section files with correct data', () async {
        final response = await sendGet('/api/v1/data/export');
        final bytes = await response.read().expand((b) => b).toList();
        final archive = ZipDecoder().decodeBytes(bytes);

        // Should have metadata + 2 sections = 3 files
        expect(archive.length, 3);

        final profilesFile = archive.findFile('profiles.json');
        expect(profilesFile, isNotNull);
        final profilesData = jsonDecode(utf8.decode(profilesFile!.content));
        expect(profilesData['profiles'], isList);
        expect((profilesData['profiles'] as List).first['id'], 'p1');

        final shotsFile = archive.findFile('shots.json');
        expect(shotsFile, isNotNull);
        final shotsData = jsonDecode(utf8.decode(shotsFile!.content));
        expect(shotsData['shots'], isList);
      });

      test(
        'continues exporting other sections when one section fails',
        () async {
          final failingSection = FailingExportSection(filename: 'failing.json');
          final goodSection = MockExportSection(
            filename: 'good.json',
            exportData: {'data': 'ok'},
          );

          final handlerWithFailure = DataExportHandler(
            sections: [failingSection, goodSection],
          );

          final app = Router().plus;
          handlerWithFailure.addRoutes(app);
          final testHandler = app.call;

          final response = await testHandler(
            Request('GET', Uri.parse('http://localhost/api/v1/data/export')),
          );

          expect(response.statusCode, 200);
          final bytes = await response.read().expand((b) => b).toList();
          final archive = ZipDecoder().decodeBytes(bytes);

          // Should have metadata + good section (failing section skipped)
          expect(archive.findFile('good.json'), isNotNull);
          expect(archive.findFile('failing.json'), isNull);
        },
      );
    });

    group('POST /api/v1/data/import', () {
      test('with valid ZIP returns import summary', () async {
        final zipBytes = buildZip({
          'metadata.json': {'formatVersion': 1, 'platform': 'macos'},
          'profiles.json': {
            'profiles': [
              {'id': 'p1'},
            ],
          },
          'shots.json': {
            'shots': [
              {'id': 's1'},
            ],
          },
        });

        final response = await sendPost('/api/v1/data/import', body: zipBytes);

        expect(response.statusCode, 200);
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;

        expect(body.containsKey('profiles'), isTrue);
        expect(body['profiles']['imported'], 1);

        expect(body.containsKey('shots'), isTrue);
        expect(body['shots']['imported'], 2);
        expect(body['shots']['skipped'], 1);
      });

      test('uses skip strategy by default', () async {
        final zipBytes = buildZip({
          'metadata.json': {'formatVersion': 1, 'platform': 'macos'},
          'profiles.json': {'profiles': []},
        });

        await sendPost('/api/v1/data/import', body: zipBytes);

        expect(profileSection.importCalled, isTrue);
        expect(profileSection.lastStrategy, ConflictStrategy.skip);
      });

      test('uses overwrite strategy when specified', () async {
        final zipBytes = buildZip({
          'metadata.json': {'formatVersion': 1, 'platform': 'macos'},
          'profiles.json': {'profiles': []},
        });

        final response = await sendPost(
          '/api/v1/data/import?onConflict=overwrite',
          body: zipBytes,
        );

        expect(response.statusCode, 200);
        expect(profileSection.lastStrategy, ConflictStrategy.overwrite);
      });

      test('returns 400 for invalid onConflict value', () async {
        final zipBytes = buildZip({
          'metadata.json': {'formatVersion': 1},
        });

        final response = await sendPost(
          '/api/v1/data/import?onConflict=invalid',
          body: zipBytes,
        );

        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], 'Invalid onConflict value');
      });

      test(
        'returns 400 when the body is not a recognized backup archive',
        () async {
          // The archive library is lenient: unrecognized bytes produce an empty
          // archive rather than throwing ArchiveException. The handler treats
          // that as "nothing to import" and returns an empty summary.
          final response = await sendPost(
            '/api/v1/data/import',
            body: [0, 1, 2, 3, 4, 5],
          );

          expect(response.statusCode, 400);
          final body = jsonDecode(await response.readAsString());
          expect(body['error'], 'Invalid backup archive');
          expect(body['message'], contains('recognized data sections'));
        },
      );

      test(
        'returns 400 for empty, unknown-only, and metadata-only archives',
        () async {
          for (final files in [
            <String, dynamic>{},
            {'notes.txt': 'unknown', 'unknown.json': {}},
            {
              'metadata.json': {'formatVersion': 1},
            },
          ]) {
            final response = await sendPost(
              '/api/v1/data/import',
              body: buildZip(files),
            );
            expect(response.statusCode, 400);
            final body = jsonDecode(await response.readAsString());
            expect(body['error'], 'Invalid backup archive');
          }
          expect(profileSection.importCalled, isFalse);
          expect(shotsSection.importCalled, isFalse);
        },
      );

      test('returns 400 when formatVersion is too high', () async {
        final zipBytes = buildZip({
          'metadata.json': {'formatVersion': 999, 'platform': 'macos'},
        });

        final response = await sendPost('/api/v1/data/import', body: zipBytes);

        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], 'Invalid backup archive');
        expect(body['message'], contains('999'));
      });

      test('returns 400 for malformed metadata', () async {
        for (final zipBytes in [
          buildZipEntries({
            'metadata.json': '{not json',
            'profiles.json': '{}',
          }),
          buildZip({
            'metadata.json': ['not an object'],
            'profiles.json': {},
          }),
          buildZip({
            'metadata.json': {'formatVersion': '1'},
            'profiles.json': {},
          }),
        ]) {
          final response = await sendPost(
            '/api/v1/data/import',
            body: zipBytes,
          );
          expect(response.statusCode, 400);
          expect(profileSection.importCalled, isFalse);
        }
      });

      test('succeeds when metadata.json is missing from archive', () async {
        final zipBytes = buildZip({
          'profiles.json': {'profiles': []},
        });

        final response = await sendPost('/api/v1/data/import', body: zipBytes);

        expect(response.statusCode, 200);
        expect(profileSection.importCalled, isTrue);
      });

      test('skips sections not present in the archive', () async {
        final zipBytes = buildZip({
          'metadata.json': {'formatVersion': 1, 'platform': 'macos'},
          'profiles.json': {'profiles': []},
          // No shots.json
        });

        final response = await sendPost('/api/v1/data/import', body: zipBytes);

        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        expect(body.containsKey('profiles'), isTrue);
        expect(body.containsKey('shots'), isFalse);
        expect(shotsSection.importCalled, isFalse);
      });

      test('returns 207 for thrown and returned section errors', () async {
        final failing = FailingExportSection(filename: 'failing.json');
        final thrownHandler = DataExportHandler(
          sections: [profileSection, failing],
        );
        final app = Router().plus;
        thrownHandler.addRoutes(app);
        final thrownResponse = await app.call(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/data/import'),
            body: buildZip({'profiles.json': {}, 'failing.json': {}}),
            headers: {'content-type': 'application/octet-stream'},
          ),
        );
        expect(thrownResponse.statusCode, 207);
        final thrownBody = jsonDecode(await thrownResponse.readAsString());
        expect(thrownBody['profiles']['imported'], 1);
        expect(thrownBody['failing']['errors'], isNotEmpty);

        final returned = MockExportSection(
          filename: 'profiles.json',
          importResult: const SectionImportResult(
            imported: 2,
            errors: ['bad row'],
          ),
        );
        final returnedHandler = DataExportHandler(sections: [returned]);
        final returnedApp = Router().plus;
        returnedHandler.addRoutes(returnedApp);
        final returnedResponse = await returnedApp.call(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/data/import'),
            body: buildZip({'profiles.json': {}}),
            headers: {'content-type': 'application/octet-stream'},
          ),
        );
        expect(returnedResponse.statusCode, 207);
        final returnedBody = jsonDecode(await returnedResponse.readAsString());
        expect(returnedBody['profiles']['imported'], 2);
        expect(returnedBody['profiles']['errors'], contains('bad row'));
      });

      test('warnings and skips alone return 200', () async {
        final warning = MockExportSection(
          filename: 'profiles.json',
          importResult: const SectionImportResult(
            skipped: 2,
            warnings: ['warning'],
          ),
        );
        final warningHandler = DataExportHandler(sections: [warning]);
        final app = Router().plus;
        warningHandler.addRoutes(app);
        final response = await app.call(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/data/import'),
            body: buildZip({'profiles.json': {}}),
            headers: {'content-type': 'application/octet-stream'},
          ),
        );
        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        expect(body['profiles']['skipped'], 2);
        expect(body['profiles']['warnings'], isNotEmpty);
      });

      test('malformed recognized JSON returns 207 and continues', () async {
        final response = await sendPost(
          '/api/v1/data/import',
          body: buildZipEntries({
            'profiles.json': '{not json',
            'shots.json': '{}',
          }),
        );
        expect(response.statusCode, 207);
        final body = jsonDecode(await response.readAsString());
        expect(body['profiles']['errors'], isNotEmpty);
        expect(body['shots']['imported'], 2);
      });

      test('all recognized sections failing return 207', () async {
        final failingHandler = DataExportHandler(
          sections: [
            FailingExportSection(filename: 'profiles.json'),
            FailingExportSection(filename: 'shots.json'),
          ],
        );
        final app = Router().plus;
        failingHandler.addRoutes(app);
        final response = await app.call(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/data/import'),
            body: buildZip({'profiles.json': {}, 'shots.json': {}}),
            headers: {'content-type': 'application/octet-stream'},
          ),
        );
        expect(response.statusCode, 207);
        final body = jsonDecode(await response.readAsString());
        expect(body.keys, containsAll(['profiles', 'shots']));
      });

      test('reports errors when a section import fails', () async {
        final failingSection = FailingExportSection(filename: 'failing.json');
        final handlerWithFailure = DataExportHandler(
          sections: [failingSection],
        );

        final app = Router().plus;
        handlerWithFailure.addRoutes(app);
        final testHandler = app.call;

        final zipBytes = buildZip({
          'metadata.json': {'formatVersion': 1, 'platform': 'macos'},
          'failing.json': {'data': 'test'},
        });

        final response = await testHandler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/data/import'),
            body: zipBytes,
            headers: {'content-type': 'application/octet-stream'},
          ),
        );

        expect(response.statusCode, 207);
        final body = jsonDecode(await response.readAsString());
        expect(body['failing']['errors'], isList);
        expect((body['failing']['errors'] as List).first, contains('Failed'));
      });
    });

    group('exportToBytes()', () {
      test('returns ZIP bytes containing all sections', () async {
        final bytes = await handler.exportToBytes();

        final archive = ZipDecoder().decodeBytes(bytes);
        expect(archive.findFile('metadata.json'), isNotNull);
        expect(archive.findFile('profiles.json'), isNotNull);
        expect(archive.findFile('shots.json'), isNotNull);
      });

      test('filters sections when specified', () async {
        final bytes = await handler.exportToBytes(sections: ['profiles']);

        final archive = ZipDecoder().decodeBytes(bytes);
        expect(archive.findFile('metadata.json'), isNotNull);
        expect(archive.findFile('profiles.json'), isNotNull);
        expect(archive.findFile('shots.json'), isNull);
      });
    });

    group('importFromBytes()', () {
      test('imports all sections from ZIP bytes', () async {
        final zipBytes = buildZip({
          'metadata.json': {'formatVersion': 1, 'platform': 'macos'},
          'profiles.json': {
            'profiles': [
              {'id': 'p1'},
            ],
          },
          'shots.json': {
            'shots': [
              {'id': 's1'},
            ],
          },
        });

        final outcome = await handler.importFromBytes(
          zipBytes,
          ConflictStrategy.skip,
        );

        expect(outcome.recognizedSections, 2);
        expect(outcome.isPartial, isFalse);
        expect(outcome.sectionResults, contains('profiles'));
        expect(outcome.sectionResults, contains('shots'));
        expect(profileSection.importCalled, isTrue);
        expect(shotsSection.importCalled, isTrue);
      });

      test('filters sections when specified', () async {
        final zipBytes = buildZip({
          'metadata.json': {'formatVersion': 1, 'platform': 'macos'},
          'profiles.json': {
            'profiles': [
              {'id': 'p1'},
            ],
          },
          'shots.json': {
            'shots': [
              {'id': 's1'},
            ],
          },
        });

        final outcome = await handler.importFromBytes(
          zipBytes,
          ConflictStrategy.skip,
          sections: ['profiles'],
        );

        expect(outcome.recognizedSections, 1);
        expect(outcome.sectionResults, contains('profiles'));
        expect(outcome.sectionResults, isNot(contains('shots')));
        expect(profileSection.importCalled, isTrue);
        expect(shotsSection.importCalled, isFalse);
      });

      test(
        'throws InvalidBackupException for invalid archives and selections',
        () async {
          final zipBytes = buildZip({
            'metadata.json': {'formatVersion': 99},
          });

          expect(
            () => handler.importFromBytes(zipBytes, ConflictStrategy.skip),
            throwsA(isA<InvalidBackupException>()),
          );

          expect(
            () => handler.importFromBytes(
              buildZip({
                'metadata.json': {'formatVersion': 1},
              }),
              ConflictStrategy.skip,
            ),
            throwsA(isA<InvalidBackupException>()),
          );
          expect(
            () => handler.importFromBytes(
              buildZip({'profiles.json': {}}),
              ConflictStrategy.skip,
              sections: ['unknown'],
            ),
            throwsA(isA<InvalidBackupException>()),
          );
          expect(
            () => handler.importFromBytes(
              buildZip({'shots.json': {}}),
              ConflictStrategy.skip,
              sections: ['profiles'],
            ),
            throwsA(isA<InvalidBackupException>()),
          );
        },
      );

      test('section errors make direct outcomes partial', () async {
        final errorSection = MockExportSection(
          filename: 'profiles.json',
          importResult: const SectionImportResult(errors: ['bad row']),
        );
        final outcome = await DataExportHandler(sections: [errorSection])
            .importFromBytes(
              buildZip({'profiles.json': {}}),
              ConflictStrategy.skip,
            );
        expect(outcome.recognizedSections, 1);
        expect(outcome.isPartial, isTrue);
        expect(outcome.failedSections, contains('profiles'));
      });

      test('thrown section errors make direct outcomes partial', () async {
        final outcome =
            await DataExportHandler(
              sections: [FailingExportSection(filename: 'profiles.json')],
            ).importFromBytes(
              buildZip({'profiles.json': {}}),
              ConflictStrategy.skip,
            );
        expect(outcome.recognizedSections, 1);
        expect(outcome.isPartial, isTrue);
        expect(outcome.sectionResults['profiles']['errors'], isNotEmpty);
      });

      test(
        'duplicate selection excludes an unselected failing section',
        () async {
          final selectedHandler = DataExportHandler(
            sections: [
              profileSection,
              FailingExportSection(filename: 'shots.json'),
            ],
          );
          final outcome = await selectedHandler.importFromBytes(
            buildZip({'profiles.json': {}, 'shots.json': {}}),
            ConflictStrategy.skip,
            sections: ['profiles', 'profiles'],
          );
          expect(outcome.recognizedSections, 1);
          expect(outcome.isPartial, isFalse);
          expect(profileSection.importCalled, isTrue);
        },
      );
    });
  });
}
