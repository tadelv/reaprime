import 'dart:typed_data';

final class De1FirmwareHeader {
  static const int byteLength = 64;
  static const int de1BoardMarker = 0xDE100001;

  final int checksum;
  final int boardMarker;
  final int firmwareVersion;
  final int bodyByteCount;
  final int cpuByteCount;
  final int unused;
  final int decryptedChecksum;
  final Uint8List initializationVector;
  final int headerChecksum;

  const De1FirmwareHeader({
    required this.checksum,
    required this.boardMarker,
    required this.firmwareVersion,
    required this.bodyByteCount,
    required this.cpuByteCount,
    required this.unused,
    required this.decryptedChecksum,
    required this.initializationVector,
    required this.headerChecksum,
  });

  factory De1FirmwareHeader.parse(Uint8List image) {
    if (image.length < byteLength) {
      throw const FormatException('Firmware image is shorter than its header');
    }
    final view = ByteData.sublistView(image);
    return De1FirmwareHeader(
      checksum: view.getUint32(0, Endian.little),
      boardMarker: view.getUint32(4, Endian.little),
      firmwareVersion: view.getUint32(8, Endian.little),
      bodyByteCount: view.getUint32(12, Endian.little),
      cpuByteCount: view.getUint32(16, Endian.little),
      unused: view.getUint32(20, Endian.little),
      decryptedChecksum: view.getUint32(24, Endian.little),
      initializationVector: Uint8List.sublistView(image, 28, 60),
      headerChecksum: view.getUint32(60, Endian.little),
    );
  }

  bool get isDe1Board => boardMarker == de1BoardMarker;
}
