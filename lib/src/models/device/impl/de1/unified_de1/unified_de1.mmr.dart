part of 'unified_de1.dart';

/// Bounded wait for an MMR notification matching the read request.
/// Without this, a single dropped notify during `onConnect` hangs the
/// entire connect call chain forever. See comms-harden #2.
const _mmrReadTimeout = Duration(seconds: 2);

extension UnifiedDe1MMR on UnifiedDe1 {
  Future<List<int>> _mmrRead(MMRItem item, {int length = 0}) async {
    _log.info("mmr read: ${item.name}");
    ByteData bytes = ByteData(20);
    bytes.setInt32(0, item.address, Endian.big);
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
          // log.info("listen where event  ${element.map(toHexString).toList()}");

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
              throw MmrTimeoutException(item.name, _mmrReadTimeout),
        );
    _log.info(
      "listen event Result:  ${result.map((e) => e.toRadixString(16)).toList()}",
    );
    return result;
  }

  Future<void> _mmrWrite(MMRItem item, List<int> bufferData) {
    _log.info("mmr write: ${item.name}");

    ByteData bytes = ByteData(20);
    bytes.setInt32(0, item.address, Endian.big);
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

  // Add MMR configuration map
  static const Map<MMRItem, _MMRConfig> _mmrConfigs = {
    MMRItem.fanThreshold: _MMRConfig(
      item: MMRItem.fanThreshold,
      minValue: 0,
      maxValue: 50,
    ),
    MMRItem.flushFlowRate: _MMRConfig(
      item: MMRItem.flushFlowRate,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.flushTemp: _MMRConfig(
      item: MMRItem.flushTemp,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.flushTimeout: _MMRConfig(
      item: MMRItem.flushTimeout,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.waterHeaterIdleTemp: _MMRConfig(
      item: MMRItem.waterHeaterIdleTemp,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.heaterUp1Flow: _MMRConfig(
      item: MMRItem.heaterUp1Flow,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.heaterUp2Flow: _MMRConfig(
      item: MMRItem.heaterUp2Flow,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.heaterUp2Timeout: _MMRConfig(
      item: MMRItem.heaterUp2Timeout,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.hotWaterFlowRate: _MMRConfig(
      item: MMRItem.hotWaterFlowRate,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.targetSteamFlow: _MMRConfig(
      item: MMRItem.targetSteamFlow,
      readScale: 0.01,
      writeScale: 100.0,
    ),
    MMRItem.tankTemp: _MMRConfig(item: MMRItem.tankTemp),
    MMRItem.allowUSBCharging: _MMRConfig(item: MMRItem.allowUSBCharging),
    MMRItem.calFlowEst: _MMRConfig(
      item: MMRItem.calFlowEst,
      readScale: 0.001,
      writeScale: 1000.0,
      minValue: 130,
      maxValue: 2000,
    ),
  };

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
    final config = _mmrConfigs[item]!;
    final rawValue = await _readMMRInt(item);
    return rawValue.toDouble() * config.readScale;
  }

  Future<void> _writeMMRInt(MMRItem item, int value) async {
    final config = _mmrConfigs[item];
    final clampedValue =
        config?.minValue != null && config?.maxValue != null
            ? min(config!.maxValue!, max(config.minValue!, value))
            : value;
    await _mmrWrite(item, _packMMRInt(clampedValue));
  }

  Future<void> _writeMMRScaled(MMRItem item, double value) async {
    final config = _mmrConfigs[item]!;
    final scaledValue = (value * config.writeScale).toInt();
    await _writeMMRInt(item, scaledValue);
  }
}
