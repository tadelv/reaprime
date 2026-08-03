import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/backup_export_response.dart';

void main() {
  test('rejects an export error before returning backup bytes', () {
    expect(
      () => BackupExportResponse.fromHttp(
        statusCode: 500,
        mimeType: 'application/json',
        bytes: Uint8List.fromList(
          '{"message":"Failed to export profiles."}'.codeUnits,
        ),
      ),
      throwsA(
        isA<BackupExportException>()
            .having((error) => error.statusCode, 'status code', 500)
            .having(
              (error) => error.message,
              'message',
              'Failed to export profiles.',
            ),
      ),
    );
  });

  test('rejects a successful response with a non-ZIP content type', () {
    expect(
      () => BackupExportResponse.fromHttp(
        statusCode: 200,
        mimeType: 'application/json',
        bytes: Uint8List.fromList('{}'.codeUnits),
      ),
      throwsA(isA<BackupExportException>()),
    );
  });

  test('accepts a successful ZIP response', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final response = BackupExportResponse.fromHttp(
      statusCode: 200,
      mimeType: 'application/zip',
      bytes: bytes,
    );

    expect(response.bytes, orderedEquals(bytes));
  });
}
