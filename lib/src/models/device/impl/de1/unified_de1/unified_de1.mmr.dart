part of 'unified_de1.dart';

/// Bounded wait for an MMR notification matching the read request.
/// Without this, a single dropped notify during `onConnect` hangs the
/// entire connect call chain forever. See comms-harden #2.
const _mmrReadTimeout = Duration(seconds: 2);

extension UnifiedDe1MMR on UnifiedDe1 {
  Future<List<int>> _mmrRead(MMRItem item, {int length = 0}) =>
      _mmrReadRaw(item.address, length: length, label: item.name);

  Future<void> _mmrWrite(MMRItem item, List<int> bufferData) =>
      _mmrWriteRaw(item.address, bufferData, label: item.name);

  /// Address-only MMR read for capability mixins whose addresses aren't
  /// in the [MMRItem] enum. Same wire behavior as [_mmrRead]; uses the
  /// hex address as the log/timeout label when no enum name is given.
  Future<List<int>> _mmrReadRaw(int address,
      {int length = 0, String? label}) async {
    final logLabel = label ?? '0x${address.toRadixString(16)}';
    _log.info("mmr read: $logLabel");
    ByteData bytes = ByteData(20);
    bytes.setInt32(0, address, Endian.big);
    var buffer = bytes.buffer.asUint8List();
    buffer[0] = (length % 0xFF);

    _log.fine(
      'sending read req ${buffer.map((e) => e.toRadixString(16)).toList()}',
    );

    await _transport.writeWithResponse(
      Endpoint.readFromMMR,
      Uint8List.fromList(buffer),
    );

    var result = await _mmr
        .map((d) => d.buffer.asUint8List().toList())
        .firstWhere((element) {
          if (buffer[1] == element[1] &&
              buffer[2] == element[2] &&
              buffer[3] == element[3]) {
            return true;
          } else {
            return false;
          }
        }, orElse: () => <int>[])
        .timeout(
          _mmrReadTimeout,
          onTimeout: () =>
              throw MmrTimeoutException(logLabel, _mmrReadTimeout),
        );
    _log.info(
      "listen event Result:  ${result.map((e) => e.toRadixString(16)).toList()}",
    );
    return result;
  }

  /// Address-only MMR write for capability mixins; see [_mmrReadRaw].
  Future<void> _mmrWriteRaw(int address, List<int> bufferData,
      {String? label}) {
    final logLabel = label ?? '0x${address.toRadixString(16)}';
    _log.info("mmr write: $logLabel");

    ByteData bytes = ByteData(20);
    bytes.setInt32(0, address, Endian.big);
    var buffer = bytes.buffer.asUint8List();
    buffer[0] = (bufferData.length % 0xFF);
    var i = 0;
    for (var _ in bufferData) {
      buffer[i + 4] = bufferData[i++];
    }
    _log.fine('payload ${bufferData.map((e) => e.toRadixString(16)).toList()}');
    return _transport.writeWithResponse(
      Endpoint.writeToMMR,
      Uint8List.fromList(buffer),
    );
  }

  int _unpackMMRInt(List<int> buffer) {
    // Defensive guard: `_mmrRead` now throws `MmrTimeoutException` on
    // missing responses and shouldn't reach here with a short buffer,
    // but an explicit error beats a downstream `RangeError` if the
    // upstream contract ever changes. The loop below reads 20 bytes.
    if (buffer.length < 20) {
      throw StateError(
        'MMR response buffer too short (got ${buffer.length} bytes, '
        'expected at least 20)',
      );
    }
    ByteData bytes = ByteData(20);
    var i = 0;
    var list = bytes.buffer.asUint8List();
    for (var _ in list) {
      list[i] = buffer[i++];
    }
    return bytes.getInt32(4, Endian.little);
  }

  Uint8List _packMMRInt(int number) {
    var bytes = ByteData(4);
    bytes.setUint32(0, number, Endian.little);
    return bytes.buffer.asUint8List();
  }

  // MMR helper methods
  Future<int> _readMMRInt(MMRItem item) async {
    final result = await _mmrRead(item);
    return _unpackMMRInt(result);
  }

  Future<double> _readMMRScaled(MMRItem item) async {
    final rawValue = await _readMMRInt(item);
    return rawValue.toDouble() * item.readScale;
  }

  Future<void> _writeMMRInt(MMRItem item, int value) async {
    final clampedValue = (item.min != null && item.max != null)
        ? value.clamp(item.min!, item.max!)
        : value;
    await _mmrWrite(item, _packMMRInt(clampedValue));
  }

  Future<void> _writeMMRScaled(MMRItem item, double value) async {
    final scaledValue = (value * item.writeScale).toInt();
    await _writeMMRInt(item, scaledValue);
  }
}
