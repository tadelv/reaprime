import 'dart:convert';

import 'package:reaprime/src/import/import_result.dart';

enum BackupImportStatus { complete, partial }

class BackupImportException implements Exception {
  final String message;
  final int? statusCode;

  const BackupImportException(this.message, {this.statusCode});

  bool get isInvalidBackup => statusCode == 400;

  @override
  String toString() => 'BackupImportException: $message';
}

class BackupImportResponse {
  final BackupImportStatus status;
  final Map<String, dynamic> sections;

  const BackupImportResponse({required this.status, required this.sections});

  bool get shouldNotifyShotsChanged => true;

  ImportResult toImportResult() => ImportResult.fromBackupSections(sections);

  factory BackupImportResponse.fromHttp(int statusCode, String body) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw BackupImportException(
        'The server returned an invalid response.',
        statusCode: statusCode,
      );
    }

    if (statusCode == 200 || statusCode == 207) {
      if (decoded is! Map) {
        throw BackupImportException(
          'The server returned an invalid import result.',
          statusCode: statusCode,
        );
      }
      return BackupImportResponse(
        status: statusCode == 207
            ? BackupImportStatus.partial
            : BackupImportStatus.complete,
        sections: Map<String, dynamic>.from(decoded),
      );
    }

    final message = decoded is Map && decoded['message'] is String
        ? decoded['message'] as String
        : 'The server returned status $statusCode.';
    throw BackupImportException(message, statusCode: statusCode);
  }
}

String backupImportDialogTitle(BackupImportStatus status) =>
    status == BackupImportStatus.partial
    ? 'Import Partially Complete'
    : 'Import Complete';
