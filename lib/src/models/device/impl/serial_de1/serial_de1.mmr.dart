part of 'serial_de1.dart';

extension De1Mmr on SerialDe1 {
  void _mmrNotification(ByteData value) {
    var list = value.buffer.asUint8List();
    _mmrController.add(list);
  }

  Future<List<int>> _mmrRead(MMRItem item, {int length = 0}) async {
    _log.info("mmr read: ${item.name}");
    ByteData bytes = ByteData(20);
    bytes.setInt32(0, item.address, Endian.big);
    var buffer = bytes.buffer.asUint8List();
    buffer[0] = (length % 0xFF);

    _log.fine('sending read req ${buffer.map(toHexString).toList()}');

    await _sendCommand(
        "<E>${buffer.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");

    var result = await _mmrController.stream.firstWhere((element) {
      // log.info("listen where event  ${element.map(toHexString).toList()}");

      if (buffer[1] == element[1] &&
          buffer[2] == element[2] &&
          buffer[3] == element[3]) {
        return true;
      } else {
        return false;
      }
    }, orElse: () => []);
    _log.info("listen event Result:  ${result.map(toHexString).toList()}");
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
    _log.fine('payload ${bufferData.map(toHexString).toList()}');
    return _sendCommand(
        "<F>${buffer.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");
  }

  int _unpackMMRInt(List<int> buffer) {
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
}
