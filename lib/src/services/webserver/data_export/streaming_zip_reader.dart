import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:reaprime/src/services/webserver/data_export/data_transfer_limits.dart';

/// Thrown when a staged ZIP cannot be read safely: malformed headers,
/// truncated data, CRC mismatches, ZIP bombs, unsupported/encrypted entries,
/// Zip64, duplicate names, or limit violations.
class ZipReadException implements Exception {
  final String message;
  final String reason;
  const ZipReadException(this.message, {required this.reason});

  @override
  String toString() => 'ZipReadException: $message';
}

/// One entry of a staged backup ZIP.
class ZipEntryInfo {
  final String name;
  final int method; // 0 = stored, 8 = deflate
  final int flags;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  final bool isDirectory;
  final bool isSymlink;

  const ZipEntryInfo({
    required this.name,
    required this.method,
    required this.flags,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.isDirectory,
    required this.isSymlink,
  });

  bool get isEncrypted => (flags & 0x1) != 0;

  bool get usesDataDescriptor => (flags & 0x8) != 0;
}

/// A file-backed ZIP reader that never materializes a whole entry or archive
/// (issue #555). Parses the end-of-central-directory and central directory
/// with bounded reads, then inflates individual entries on demand from the
/// staged file, enforcing size caps, CRC, and size consistency.
class StreamingZipReader {
  static const _eocdSignature = 0x06054b50;
  static const _cdSignature = 0x02014b50;
  static const _localSignature = 0x04034b50;
  static const _descriptorSignature = 0x08074b50;

  final File _file;
  final RandomAccessFile _raf;
  final DataTransferLimits _limits;

  final List<ZipEntryInfo> _entries = [];
  final Map<String, ZipEntryInfo> _byName = {};

  StreamingZipReader._(this._file, this._raf, this._limits);

  /// Opens and validates a staged ZIP file. Throws [ZipReadException] on any
  /// structural problem. The caller owns [file]'s lifecycle.
  static Future<StreamingZipReader> open(
    File file,
    DataTransferLimits limits,
  ) async {
    final raf = await file.open(mode: FileMode.read);
    final reader = StreamingZipReader._(file, raf, limits);
    try {
      await reader._readCentralDirectory();
    } catch (_) {
      await raf.close();
      rethrow;
    }
    return reader;
  }

  List<ZipEntryInfo> get entries => List.unmodifiable(_entries);

  ZipEntryInfo? findEntry(String name) => _byName[name];

  /// Closes the underlying file handle. Safe to call multiple times.
  Future<void> close() async {
    try {
      await _raf.close();
    } catch (_) {
      // Best effort.
    }
  }

  /// Streams the decompressed bytes of [entry] in bounded chunks.
  ///
  /// Throws [ZipReadException] on truncated input, CRC mismatch, size
  /// mismatch, or decompression errors. The stream must be fully consumed
  /// (or cancelled) before reading another entry.
  Stream<List<int>> readEntryChunks(ZipEntryInfo entry) async* {
    if (entry.isDirectory) {
      throw const ZipReadException(
        'Cannot read content of a directory entry.',
        reason: 'invalid_zip',
      );
    }
    if (entry.isSymlink) {
      throw const ZipReadException(
        'Cannot read content of a symlink entry.',
        reason: 'invalid_zip',
      );
    }

    // Local header.
    final local = await _readAt(entry.localHeaderOffset, 30);
    final sig = _uint32(local, 0);
    if (sig != _localSignature) {
      throw const ZipReadException(
        'Malformed ZIP entry header.',
        reason: 'invalid_zip',
      );
    }
    final localFlags = _uint16(local, 6);
    final nameLen = _uint16(local, 26);
    final extraLen = _uint16(local, 28);
    final dataStart = entry.localHeaderOffset + 30 + nameLen + extraLen;
    if (dataStart + entry.compressedSize > await _file.length()) {
      throw const ZipReadException(
        'ZIP entry extends past the end of the archive.',
        reason: 'truncated_zip',
      );
    }

    var crc = 0;
    var produced = 0;
    final cap = entry.uncompressedSize;

    if (entry.method == 8) {
      // Deflate.
      final accumulator = _ChunkAccumulator();
      final decoder = ZLibCodec(
        raw: true,
        level: 6,
      ).decoder.startChunkedConversion(accumulator);
      var remaining = entry.compressedSize;
      try {
        await _raf.setPosition(dataStart);
        while (remaining > 0) {
          final chunk = await _raf.read(
            remaining < 64 * 1024 ? remaining : 64 * 1024,
          );
          if (chunk.isEmpty) {
            throw const ZipReadException(
              'Unexpected end of ZIP entry data.',
              reason: 'truncated_zip',
            );
          }
          remaining -= chunk.length;
          decoder.add(chunk);
          for (final out in accumulator.drain()) {
            crc = getCrc32(out, crc);
            produced += out.length;
            if (produced > cap) {
              throw const ZipReadException(
                'ZIP entry exceeds its declared or permitted size.',
                reason: 'entry_too_large',
              );
            }
            yield out;
          }
        }
        decoder.close();
        for (final out in accumulator.drain()) {
          crc = getCrc32(out, crc);
          produced += out.length;
          if (produced > cap) {
            throw const ZipReadException(
              'ZIP entry exceeds its declared or permitted size.',
              reason: 'entry_too_large',
            );
          }
          yield out;
        }
      } on ZipReadException {
        rethrow;
      } catch (e) {
        throw ZipReadException(
          'Failed to decompress ZIP entry: $e',
          reason: 'invalid_zip',
        );
      }
    } else if (entry.method == 0) {
      // Stored.
      await _raf.setPosition(dataStart);
      var remaining = entry.compressedSize;
      while (remaining > 0) {
        final chunk = await _raf.read(
          remaining < 64 * 1024 ? remaining : 64 * 1024,
        );
        if (chunk.isEmpty) {
          throw const ZipReadException(
            'Unexpected end of ZIP entry data.',
            reason: 'truncated_zip',
          );
        }
        remaining -= chunk.length;
        crc = getCrc32(chunk, crc);
        produced += chunk.length;
        if (produced > cap) {
          throw const ZipReadException(
            'ZIP entry exceeds its declared or permitted size.',
            reason: 'entry_too_large',
          );
        }
        yield chunk;
      }
    } else {
      throw const ZipReadException(
        'Unsupported ZIP compression method.',
        reason: 'unsupported_entry',
      );
    }

    // Data descriptor (local header may carry sizes already; the descriptor
    // is authoritative only for its CRC — we verify against the CD values).
    if (localFlags & 0x8 != 0) {
      final descriptor = await _readAt(dataStart + entry.compressedSize, 16);
      var offset = 0;
      final first = _uint32(descriptor, 0);
      if (first == _descriptorSignature) {
        offset = 4;
      }
      final descriptorCrc = offset == 0 ? first : _uint32(descriptor, 4);
      if (descriptorCrc != entry.crc32) {
        throw const ZipReadException(
          'ZIP entry CRC mismatch.',
          reason: 'crc_mismatch',
        );
      }
    }

    if (produced != entry.uncompressedSize) {
      throw ZipReadException(
        'ZIP entry size mismatch: expected ${entry.uncompressedSize} bytes, got $produced.',
        reason: 'truncated_zip',
      );
    }
    if (crc != entry.crc32) {
      throw const ZipReadException(
        'ZIP entry CRC mismatch.',
        reason: 'crc_mismatch',
      );
    }
  }

  /// Reads the whole decompressed content of [entry] into memory, enforcing
  /// [maxBytes]. For small entries only (metadata.json).
  Future<Uint8List> readEntryBytes(
    ZipEntryInfo entry, {
    required int maxBytes,
  }) async {
    if (entry.uncompressedSize > maxBytes) {
      throw ZipReadException(
        'ZIP entry exceeds the ${maxBytes}-byte limit.',
        reason: 'entry_too_large',
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in readEntryChunks(entry)) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw ZipReadException(
          'ZIP entry exceeds the ${maxBytes}-byte limit.',
          reason: 'entry_too_large',
        );
      }
    }
    return builder.takeBytes();
  }

  // ---- central directory parsing ----

  Future<void> _readCentralDirectory() async {
    final length = await _file.length();
    if (length < 22) {
      throw const ZipReadException(
        'The archive is too small to be a ZIP file.',
        reason: 'invalid_zip',
      );
    }

    // EOCD scan from the tail (max comment 65535 + 22-byte record).
    final tailStart = length > 65557 ? length - 65557 : 0;
    final tail = await _readAt(tailStart, length - tailStart);
    int? eocdPos;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (_uint32(tail, i) == _eocdSignature) {
        final commentLen = _uint16(tail, i + 20);
        if (tailStart + i + 22 + commentLen == length) {
          eocdPos = tailStart + i;
          break;
        }
      }
    }
    if (eocdPos == null) {
      throw const ZipReadException(
        'Could not find the ZIP end-of-central-directory record.',
        reason: 'invalid_zip',
      );
    }
    final eocd = await _readAt(eocdPos, 22);
    final entriesOnDisk = _uint16(eocd, 8);
    final totalEntries = _uint16(eocd, 10);
    final cdSize = _uint32(eocd, 12);
    final cdOffset = _uint32(eocd, 16);

    if (entriesOnDisk == 0xFFFF ||
        totalEntries == 0xFFFF ||
        cdSize == 0xFFFFFFFF ||
        cdOffset == 0xFFFFFFFF) {
      throw const ZipReadException(
        'ZIP64 archives are not supported.',
        reason: 'zip64_unsupported',
      );
    }
    if (entriesOnDisk != totalEntries) {
      throw const ZipReadException(
        'Multi-disk or inconsistent ZIP archives are not supported.',
        reason: 'invalid_zip',
      );
    }
    if (totalEntries > _limits.maxEntryCount) {
      throw const ZipReadException(
        'The archive contains too many entries.',
        reason: 'too_many_entries',
      );
    }
    final maxCdSize =
        totalEntries *
        (46 +
            _limits.maxFilenameBytes +
            _limits.maxExtraFieldBytes +
            _limits.maxCommentBytes);
    if (cdSize > maxCdSize || cdOffset + cdSize > length) {
      throw const ZipReadException(
        'The ZIP central directory is malformed or oversized.',
        reason: 'invalid_zip',
      );
    }

    // Walk the central directory entry by entry.
    var pos = cdOffset;
    var totalUncompressed = 0;
    for (var i = 0; i < totalEntries; i++) {
      final header = await _readAt(pos, 46);
      if (_uint32(header, 0) != _cdSignature) {
        throw const ZipReadException(
          'Malformed ZIP central directory.',
          reason: 'invalid_zip',
        );
      }
      final flags = _uint16(header, 8);
      final method = _uint16(header, 10);
      final crc32 = _uint32(header, 16);
      final compressedSize = _uint32(header, 20);
      final uncompressedSize = _uint32(header, 24);
      final nameLen = _uint16(header, 28);
      final extraLen = _uint16(header, 30);
      final commentLen = _uint16(header, 32);
      final externalAttrs = _uint32(header, 38);
      final localHeaderOffset = _uint32(header, 42);

      if (nameLen > _limits.maxFilenameBytes ||
          extraLen > _limits.maxExtraFieldBytes ||
          commentLen > _limits.maxCommentBytes) {
        throw const ZipReadException(
          'ZIP entry header fields exceed size limits.',
          reason: 'invalid_zip',
        );
      }
      if (localHeaderOffset == 0xFFFFFFFF ||
          compressedSize == 0xFFFFFFFF ||
          uncompressedSize == 0xFFFFFFFF) {
        throw const ZipReadException(
          'ZIP64 archives are not supported.',
          reason: 'zip64_unsupported',
        );
      }

      final rest = await _readAt(pos + 46, nameLen + extraLen + commentLen);
      final name = utf8.decode(rest.sublist(0, nameLen), allowMalformed: true);

      final unixMode = (externalAttrs >> 16) & 0xF000;
      final isDirectory =
          name.endsWith('/') || name.endsWith('\\') || unixMode == 0x4000;
      final isSymlink = unixMode == 0xA000;

      if (_byName.containsKey(name)) {
        throw ZipReadException(
          'The archive contains duplicate entry "$name".',
          reason: 'duplicate_entry',
        );
      }

      final info = ZipEntryInfo(
        name: name,
        method: method,
        flags: flags,
        crc32: crc32,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localHeaderOffset,
        isDirectory: isDirectory,
        isSymlink: isSymlink,
      );
      _entries.add(info);
      _byName[name] = info;

      if (!isDirectory) {
        if (uncompressedSize > _limits.maxEntryUncompressedBytes) {
          throw const ZipReadException(
            'ZIP entry exceeds the uncompressed size limit.',
            reason: 'entry_too_large',
          );
        }
        totalUncompressed += uncompressedSize;
        if (totalUncompressed > _limits.maxTotalUncompressedBytes) {
          throw const ZipReadException(
            'The archive exceeds the total uncompressed size limit.',
            reason: 'total_too_large',
          );
        }
        if (method != 8 && method != 0) {
          throw const ZipReadException(
            'ZIP entry uses an unsupported compression method.',
            reason: 'unsupported_entry',
          );
        }
        if (flags & 0x1 != 0) {
          throw const ZipReadException(
            'ZIP entry is encrypted.',
            reason: 'encrypted_entry',
          );
        }
        if (localHeaderOffset + 30 + nameLen + extraLen + compressedSize >
            cdOffset) {
          throw const ZipReadException(
            'ZIP entry data overlaps the central directory.',
            reason: 'invalid_zip',
          );
        }
      }

      pos += 46 + nameLen + extraLen + commentLen;
      if (pos > cdOffset + cdSize) {
        throw const ZipReadException(
          'ZIP central directory is truncated.',
          reason: 'invalid_zip',
        );
      }
    }
  }

  Future<Uint8List> _readAt(int offset, int length) async {
    await _raf.setPosition(offset);
    final bytes = await _raf.read(length);
    if (bytes.length != length) {
      throw const ZipReadException(
        'Unexpected end of archive while reading.',
        reason: 'truncated_zip',
      );
    }
    return bytes;
  }

  static int _uint16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

  static int _uint32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
}

/// Collects decoder output between drains so an async* generator can yield
/// bounded decompressed chunks.
class _ChunkAccumulator implements Sink<List<int>> {
  final List<Uint8List> _pending = [];

  @override
  void add(List<int> chunk) {
    _pending.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
  }

  @override
  void close() {}

  List<Uint8List> drain() {
    if (_pending.isEmpty) return const [];
    final result = _pending.toList(growable: false);
    _pending.clear();
    return result;
  }
}
