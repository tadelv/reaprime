import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:reaprime/src/settings/backup_import_response.dart';

/// Raised when a native backup transfer fails (bad status, wrong MIME,
/// oversized response, or I/O error).
class BackupTransferException implements Exception {
  final String message;
  final int? statusCode;

  const BackupTransferException(this.message, {this.statusCode});

  @override
  String toString() => 'BackupTransferException: $message';
}

/// Native full-backup transfer logic, extracted from the settings page so it
/// can be tested without a platform picker or share sheet.
///
/// Everything here is file-stream based: exports are downloaded into a
/// uniquely owned temp directory (never accumulated in a `BytesBuilder`) and
/// imports stream the picked file into the localhost request (never
/// `readAsBytes()` + `request.add(bytes)`).
class BackupTransferService {
  final HttpClient _client;
  final int maxResponseBytes;

  BackupTransferService({
    HttpClient? client,
    this.maxResponseBytes = 8 * 1024 * 1024,
  }) : _client = client ?? HttpClient();

  /// GETs [url], validates status 200 and `application/zip` MIME, and streams
  /// the body into [tempDir]/export.zip. Returns the completed temp file.
  ///
  /// Throws [BackupTransferException] on bad status/MIME or stream errors.
  Future<File> downloadExportZip(String url, Directory tempDir) async {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode != 200) {
      final message = await _readErrorBody(response);
      throw BackupTransferException(
        message ?? 'The server returned status ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    final mime = response.headers.contentType?.mimeType.toLowerCase();
    if (mime != 'application/zip') {
      throw const BackupTransferException(
        'The server returned an invalid backup archive.',
      );
    }

    final file = File('${tempDir.path}${Platform.pathSeparator}export.zip');
    final raf = await file.open(mode: FileMode.write);
    try {
      await for (final chunk in response) {
        raf.writeFromSync(chunk);
      }
    } finally {
      await raf.close();
    }
    return file;
  }

  /// POSTs a backup ZIP to [url] (with `?onConflict=`), streaming either a
  /// local file ([filePath]) or an arbitrary byte stream ([readStream]).
  ///
  /// Returns the parsed [BackupImportResponse]. [contentLength] should be
  /// supplied when known so the request is not chunked.
  Future<BackupImportResponse> uploadZip(
    String url,
    String onConflict, {
    String? filePath,
    Stream<List<int>>? readStream,
    int? contentLength,
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: {
        ...Uri.parse(url).queryParameters,
        'onConflict': onConflict,
      },
    );
    final request = await _client.postUrl(uri);
    request.headers.contentType = ContentType('application', 'zip');

    final Stream<List<int>> body;
    if (filePath != null) {
      final file = File(filePath);
      request.contentLength = contentLength ?? await file.length();
      body = file.openRead();
    } else if (readStream != null) {
      body = readStream;
    } else {
      throw const BackupTransferException(
        'Could not access the selected file.',
      );
    }

    await request.addStream(body);
    final response = await request.close();
    final responseBody = await _readBounded(response);
    return BackupImportResponse.fromHttp(response.statusCode, responseBody);
  }

  Future<String?> _readErrorBody(HttpClientResponse response) async {
    try {
      final bytes = await _readBounded(response);
      final decoded = jsonDecode(bytes);
      final message = decoded is Map ? decoded['message'] : null;
      return message is String && message.isNotEmpty ? message : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _readBounded(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > maxResponseBytes) {
        throw const BackupTransferException(
          'The server response is too large.',
        );
      }
    }
    return utf8.decode(builder.takeBytes());
  }

  void close() {
    _client.close(force: true);
  }
}
