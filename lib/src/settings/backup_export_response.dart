import 'dart:convert';
import 'dart:typed_data';

class BackupExportException implements Exception {
  final String message;
  final int? statusCode;

  const BackupExportException(this.message, {this.statusCode});

  @override
  String toString() => 'BackupExportException: $message';
}

class BackupExportResponse {
  final Uint8List bytes;

  const BackupExportResponse(this.bytes);

  factory BackupExportResponse.fromHttp({
    required int statusCode,
    required String? mimeType,
    required List<int> bytes,
  }) {
    if (statusCode != 200) {
      throw BackupExportException(
        _serverMessage(bytes) ?? 'The server returned status $statusCode.',
        statusCode: statusCode,
      );
    }
    if (mimeType?.toLowerCase() != 'application/zip') {
      throw const BackupExportException(
        'The server returned an invalid backup archive.',
      );
    }
    return BackupExportResponse(Uint8List.fromList(bytes));
  }

  static String? _serverMessage(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      final message = decoded is Map ? decoded['message'] : null;
      return message is String && message.isNotEmpty ? message : null;
    } catch (_) {
      return null;
    }
  }
}
