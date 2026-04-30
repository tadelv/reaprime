import 'dart:typed_data';

/// MMR request/response encoding for the DE1 serial protocol, factored
/// out so detection can probe the v13Model MMR without a full
/// `UnifiedDe1` instance. Mirrors what `unified_de1.mmr.dart` does with
/// `_transport.writeWithResponse`, but operates directly on the wire
/// bytes.
///
/// The DE1 MMR protocol packs `[length, addr_high, addr_mid, addr_low,
/// value_b0..b3, ...]` into 20 bytes. `setInt32(0, addr, big-endian)`
/// writes the address into bytes 0..3, then byte 0 is overwritten with
/// the read length — so the addr is effectively 24-bit.

/// Builds the 20-byte MMR-read request payload for [address] with
/// [length] bytes of expected data. The caller hex-encodes the result
/// and sends it as `<F>${hex}` over the serial transport.
Uint8List buildMmrReadRequest({required int address, required int length}) {
  final bytes = ByteData(20);
  bytes.setInt32(0, address, Endian.big);
  final buf = bytes.buffer.asUint8List();
  buf[0] = length & 0xFF;
  return buf;
}

/// Decodes a serial MMR-read response line of the form `[E]hex...` into
/// a 32-bit little-endian int value, but only when bytes [1..3] of the
/// payload match [expectedAddr]. Returns null when the line is the
/// wrong shape, has malformed hex, or carries a different address.
///
/// The address is encoded big-endian in bytes [1..3], but the value
/// payload at bytes [4..7] is little-endian — matches what
/// `unified_de1.mmr.dart::_unpackMMRInt` does.
int? decodeMmrInt32Response(
  String line, {
  required (int, int, int) expectedAddr,
}) {
  if (!line.startsWith('[E]')) return null;
  final hex = line.substring(3);
  final bytes = _tryParseHex(hex);
  if (bytes == null) return null;
  if (bytes.length < 8) return null;
  if (bytes[1] != expectedAddr.$1 ||
      bytes[2] != expectedAddr.$2 ||
      bytes[3] != expectedAddr.$3) {
    return null;
  }
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return view.getInt32(4, Endian.little);
}

Uint8List? _tryParseHex(String hex) {
  if (hex.length.isOdd) return null;
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    final b = int.tryParse(hex.substring(i, i + 2), radix: 16);
    if (b == null) return null;
    out[i ~/ 2] = b;
  }
  return out;
}
