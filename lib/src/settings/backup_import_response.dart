import 'dart:convert';

enum BackupImportStatus { complete, partial, failed }

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
            ? _statusForSections(Map<String, dynamic>.from(decoded))
            : BackupImportStatus.complete,
        sections: Map<String, dynamic>.from(decoded),
      );
    }

    final message = decoded is Map && decoded['message'] is String
        ? decoded['message'] as String
        : 'The server returned status $statusCode.';
    throw BackupImportException(message, statusCode: statusCode);
  }

  static BackupImportStatus _statusForSections(Map<String, dynamic> sections) =>
      sections.values.any(_hasProgress)
      ? BackupImportStatus.partial
      : BackupImportStatus.failed;

  static bool _hasProgress(dynamic value) {
    if (value is! Map) return false;
    final status = value['status'];
    if (status == 'complete' || status == 'partial') return true;
    return _positiveCount(value['imported']) ||
        _positiveCount(value['skipped']);
  }

  static bool _positiveCount(dynamic value) => value is int && value > 0;
}

String backupImportDialogTitle(BackupImportStatus status) => switch (status) {
  BackupImportStatus.complete => 'Import Complete',
  BackupImportStatus.partial => 'Import Partially Complete',
  BackupImportStatus.failed => 'Import Completed with Errors',
};
