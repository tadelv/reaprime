import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/backup_import_response.dart';

void main() {
  test('200 parses as complete', () {
    final response = BackupImportResponse.fromHttp(
      200,
      '{"profiles":{"imported":4,"skipped":1}}',
    );
    expect(response.status, BackupImportStatus.complete);
    expect(response.sections['profiles']['imported'], 4);
  });

  test('207 parses as partial and preserves section details', () {
    final response = BackupImportResponse.fromHttp(
      207,
      '{"profiles":{"imported":4},"shots":{"errors":["bad row"]}}',
    );
    expect(response.status, BackupImportStatus.partial);
    expect(response.sections['profiles']['imported'], 4);
    expect(response.sections['shots']['errors'], contains('bad row'));
  });

  test('partial UI state does not use complete wording', () {
    expect(
      backupImportDialogTitle(BackupImportStatus.partial),
      'Import Partially Complete',
    );
    expect(
      backupImportDialogTitle(BackupImportStatus.partial),
      isNot('Import Complete'),
    );
  });

  test('partial response can notify changed data', () {
    final response = BackupImportResponse.fromHttp(207, '{}');
    expect(response.shouldNotifyShotsChanged, isTrue);
  });

  test('400 preserves the invalid-backup server message', () {
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
              contains('recognized'),
            ),
      ),
    );
  });

  test('archive-level failure does not produce a refresh response', () {
    expect(
      () => BackupImportResponse.fromHttp(400, '{"message":"invalid"}'),
      throwsA(isA<BackupImportException>()),
    );
  });
}
