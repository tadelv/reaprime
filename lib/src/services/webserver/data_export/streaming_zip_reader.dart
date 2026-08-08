import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:reaprime/src/services/webserver/data_export/data_transfer_limits.dart';

class ZipReadException implements Exception {
  final String message;
  final String reason;

  const ZipReadException(this.message, {required this.reason});

  @override
  String toString() => 'ZipReadException: $message';
}

class StreamingZipReader {
  final InputFileStream _input;
  final Archive _archive;
  final DataTransferLimits _limits;

  StreamingZipReader._(this._input, this._archive, this._limits);

  static Future<StreamingZipReader> open(
    File file,
    DataTransferLimits limits,
  ) async {
    final input = InputFileStream(file.path);
    try {
      final decoder = ZipDecoder();
      final archive = decoder.decodeStream(input);
      final reader = StreamingZipReader._(input, archive, limits);
      reader._preflight(decoder);
      return reader;
    } on ZipReadException {
      await input.close();
      rethrow;
    } catch (e) {
      await input.close();
      throw ZipReadException(
        'Could not decode the ZIP archive: $e',
        reason: 'invalid_zip',
      );
    }
  }

  List<ArchiveFile> get entries => _archive.files;

  ArchiveFile? findEntry(String name) => _archive.findFile(name);

  void preflightSelectedEntries(Iterable<String> names) {
    for (final name in names) {
      final entry = findEntry(name);
      if (entry == null) continue;
      if (!entry.isFile || entry.isSymbolicLink) {
        throw ZipReadException(
          'Selected ZIP entry "$name" is not a regular file.',
          reason: 'invalid_zip',
        );
      }
    }
  }

  Future<void> writeEntryToFile(
    ArchiveFile entry,
    File file, {
    int? maxBytes,
  }) async {
    final limit = maxBytes ?? _limits.maxEntryUncompressedBytes;
    if (entry.size > limit) {
      throw ZipReadException(
        'ZIP entry exceeds the $limit-byte limit.',
        reason: 'entry_too_large',
      );
    }
    if (await file.exists()) await file.delete();

    final output = _BoundedOutputFileStream(
      file.path,
      entry.size < limit ? entry.size : limit,
    );
    final zipFile = entry.rawContent;
    if (zipFile is ZipFile) zipFile.getStream(decompress: false).reset();
    var complete = false;
    try {
      entry.writeContent(output, freeMemory: false);
      output.closeSync();
      if (output.length != entry.size) {
        throw ZipReadException(
          'ZIP entry size mismatch: expected ${entry.size} bytes, got ${output.length}.',
          reason: 'truncated_zip',
        );
      }
      final expectedCrc = zipFile is ZipFile
          ? zipFile.header?.crc32
          : entry.crc32;
      if (expectedCrc == null || output.crc32 != expectedCrc) {
        throw const ZipReadException(
          'ZIP entry CRC mismatch.',
          reason: 'crc_mismatch',
        );
      }
      complete = true;
    } on ZipReadException {
      rethrow;
    } catch (e) {
      throw ZipReadException(
        'Failed to decompress ZIP entry: $e',
        reason: 'invalid_zip',
      );
    } finally {
      if (zipFile is ZipFile) zipFile.getStream(decompress: false).reset();
      output.closeSync();
      if (!complete && await file.exists()) await file.delete();
    }
  }

  Future<void> close() async {
    await _archive.clear();
    await _input.close();
  }

  void _preflight(ZipDecoder decoder) {
    final directory = decoder.directory;
    final headers = directory.fileHeaders;
    final entryCount = directory.totalCentralDirectoryEntries;
    if (entryCount == 0xFFFF ||
        directory.totalCentralDirectoryEntriesOnThisDisk == 0xFFFF ||
        directory.centralDirectorySize > DataTransferLimits.maxZip32 ||
        directory.centralDirectoryOffset > DataTransferLimits.maxZip32) {
      throw const ZipReadException(
        'ZIP64 archives are not supported.',
        reason: 'zip64_unsupported',
      );
    }
    if (directory.filePosition < 0 || headers.length != entryCount) {
      throw const ZipReadException(
        'The ZIP central directory is missing or truncated.',
        reason: 'invalid_zip',
      );
    }
    if (directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0 ||
        directory.totalCentralDirectoryEntriesOnThisDisk != entryCount) {
      throw const ZipReadException(
        'Multi-disk ZIP archives are not supported.',
        reason: 'invalid_zip',
      );
    }
    if (entryCount > _limits.maxEntryCount) {
      throw const ZipReadException(
        'The archive contains too many entries.',
        reason: 'too_many_entries',
      );
    }

    final names = <String>{};
    var totalUncompressed = 0;
    for (final header in headers) {
      if (!names.add(header.filename)) {
        throw ZipReadException(
          'The archive contains duplicate entry "${header.filename}".',
          reason: 'duplicate_entry',
        );
      }
      if (utf8.encode(header.filename).length > _limits.maxFilenameBytes ||
          (header.extraField?.length ?? 0) > _limits.maxExtraFieldBytes ||
          utf8.encode(header.fileComment).length > _limits.maxCommentBytes ||
          (header.file?.extraField?.length ?? 0) > _limits.maxExtraFieldBytes) {
        throw const ZipReadException(
          'ZIP entry header fields exceed size limits.',
          reason: 'invalid_zip',
        );
      }
      if (header.uncompressedSize > DataTransferLimits.maxZip32 ||
          header.compressedSize > DataTransferLimits.maxZip32 ||
          header.localHeaderOffset > DataTransferLimits.maxZip32) {
        throw const ZipReadException(
          'ZIP64 archives are not supported.',
          reason: 'zip64_unsupported',
        );
      }
      if (header.uncompressedSize > _limits.maxEntryUncompressedBytes) {
        throw const ZipReadException(
          'ZIP entry exceeds the uncompressed size limit.',
          reason: 'entry_too_large',
        );
      }
      totalUncompressed += header.uncompressedSize;
      if (totalUncompressed > _limits.maxTotalUncompressedBytes) {
        throw const ZipReadException(
          'The archive exceeds the total uncompressed size limit.',
          reason: 'total_too_large',
        );
      }
      if (header.compressionMethod != 0 && header.compressionMethod != 8) {
        throw const ZipReadException(
          'ZIP entry uses an unsupported compression method.',
          reason: 'unsupported_entry',
        );
      }
      if (header.generalPurposeBitFlag & 0x1 != 0) {
        throw const ZipReadException(
          'ZIP entry is encrypted.',
          reason: 'encrypted_entry',
        );
      }
    }
  }
}

class _BoundedOutputFileStream extends OutputFileStream {
  final int maxBytes;
  int crc32 = 0;

  _BoundedOutputFileStream(String path, this.maxBytes)
    : super.withFileHandle(
        FileHandle(path, mode: FileAccess.write),
        bufferSize: 64 * 1024,
      );

  @override
  void writeByte(int value) {
    if (length >= maxBytes) {
      throw const ZipReadException(
        'ZIP entry exceeds its declared or permitted size.',
        reason: 'entry_too_large',
      );
    }
    crc32 = getCrc32Byte(crc32, value);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (this.length + count > maxBytes) {
      throw const ZipReadException(
        'ZIP entry exceeds its declared or permitted size.',
        reason: 'entry_too_large',
      );
    }
    crc32 = getCrc32(
      count == bytes.length ? bytes : bytes.sublist(0, count),
      crc32,
    );
    super.writeBytes(bytes, length: count);
  }
}
