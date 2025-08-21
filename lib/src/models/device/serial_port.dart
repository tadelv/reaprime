import 'package:flutter/foundation.dart';

abstract class SerialTransport {
  String get name;
  bool get isReady;
  Future<void> open();
  Future<void> close();
  // TODO: be more specific?
  Future<void> writeCommand(String command);
  Future<void> writeHexCommand(Uint8List command);
  Stream<String> get readStream;
  Stream<Uint8List> get rawStream;
}
