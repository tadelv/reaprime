import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class BackupExportException implements Exception {
  final int? statusCode;
  final String message;

  const BackupExportException({this.statusCode, required this.message});

  @override
  String toString() => 'BackupExportException: $message';
}

Future<Uint8List> downloadFullBackup({
  required http.Client client,
  Uri? uri,
}) async {
  final response = await client.get(
    uri ?? Uri.parse('http://localhost:8080/api/v1/data/export'),
  );
  final mediaType = response.headers['content-type']
      ?.split(';')
      .first
      .trim()
      .toLowerCase();

  if (response.statusCode != 200) {
    final details = _errorDetails(response.bodyBytes);
    final suffix = details.isEmpty ? '' : ': $details';
    throw BackupExportException(
      statusCode: response.statusCode,
      message: 'Backup export failed with HTTP ${response.statusCode}$suffix',
    );
  }

  if (mediaType != 'application/zip') {
    throw BackupExportException(
      statusCode: response.statusCode,
      message: 'Backup export returned unexpected content type "$mediaType".',
    );
  }

  return response.bodyBytes;
}

Future<String?> downloadAndSaveFullBackup({
  required http.Client client,
  required Future<String?> Function(Uint8List bytes) save,
}) async {
  final bytes = await downloadFullBackup(client: client);
  return save(bytes);
}

String _errorDetails(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, dynamic>) {
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) return message;
      final error = decoded['error'];
      if (error is String && error.isNotEmpty) return error;
    }
  } catch (_) {}

  return utf8.decode(bytes, allowMalformed: true).trim();
}
