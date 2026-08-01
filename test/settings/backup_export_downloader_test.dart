import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:reaprime/src/settings/backup_export_downloader.dart';

void main() {
  test('returns the exact bytes from a ZIP response', () async {
    final client = http_testing.MockClient(
      (_) async => http.Response.bytes(
        [1, 2, 3, 4],
        200,
        headers: {'content-type': 'application/zip'},
      ),
    );

    final bytes = await downloadFullBackup(client: client);

    expect(bytes, [1, 2, 3, 4]);
  });

  test('throws with the server message for a JSON error response', () async {
    final client = http_testing.MockClient(
      (_) async => http.Response(
        '{"error":"Backup export failed","message":"No backup archive was created."}',
        500,
        headers: {'content-type': 'application/json'},
      ),
    );

    await expectLater(
      downloadFullBackup(client: client),
      throwsA(
        isA<BackupExportException>().having(
          (error) => error.message,
          'message',
          contains('No backup archive was created'),
        ),
      ),
    );
  });

  test('rejects a successful response with a non-ZIP media type', () async {
    final client = http_testing.MockClient(
      (_) async => http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    await expectLater(
      downloadFullBackup(client: client),
      throwsA(
        isA<BackupExportException>().having(
          (error) => error.message,
          'message',
          contains('application/json'),
        ),
      ),
    );
  });

  test('does not call the save action after a failed download', () async {
    final client = http_testing.MockClient(
      (_) async => http.Response(
        '{"message":"No backup archive was created."}',
        500,
        headers: {'content-type': 'application/json'},
      ),
    );
    var saveCalls = 0;

    await expectLater(
      downloadAndSaveFullBackup(
        client: client,
        save: (_) async {
          saveCalls++;
          return 'backup.zip';
        },
      ),
      throwsA(isA<BackupExportException>()),
    );

    expect(saveCalls, 0);
  });
}
