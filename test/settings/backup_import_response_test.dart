import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/backup_import_response.dart';

void main() {
  test('200 parses as a complete import', () {
    final response = BackupImportResponse.fromHttp(
      200,
      '{"profiles":{"imported":4,"skipped":1}}',
    );

    expect(response.status, BackupImportStatus.complete);
    expect(response.sections['profiles']['imported'], 4);
  });

  test('207 parses as a partial import', () {
    final response = BackupImportResponse.fromHttp(
      207,
      '{"profiles":{"imported":4},"shots":{"errors":["bad row"]}}',
    );

    expect(response.status, BackupImportStatus.partial);
    expect(response.sections['profiles']['imported'], 4);
    expect(response.sections['shots']['errors'], contains('bad row'));
  });

  test('partial UI state does not use complete-success wording', () {
    expect(
      backupImportDialogTitle(BackupImportStatus.partial),
      'Import Partially Complete',
    );
    expect(
      backupImportDialogTitle(BackupImportStatus.partial),
      isNot('Import Complete'),
    );
  });

  test('partial results can refresh changed data', () {
    final response = BackupImportResponse.fromHttp(207, '{}');

    expect(response.shouldNotifyShotsChanged, isTrue);
  });

  test('400 produces an invalid-backup failure with the server message', () {
    expect(
      () => BackupImportResponse.fromHttp(
        400,
        '{"error":"Invalid backup archive","message":"No recognized data sections."}',
      ),
      throwsA(
        isA<BackupImportException>()
            .having((error) => error.isInvalidBackup, 'invalid backup', isTrue)
            .having(
              (error) => error.message,
              'message',
              contains('No recognized'),
            ),
      ),
    );
  });

  test('archive-level failure has no refresh response', () {
    var refreshed = false;
    try {
      BackupImportResponse.fromHttp(
        400,
        '{"message":"Invalid backup archive"}',
      );
      refreshed = true;
    } on BackupImportException {
      refreshed = false;
    }

    expect(refreshed, isFalse);
  });
}
