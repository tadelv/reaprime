abstract class SerialTransport {
  String get name;
  bool get isReady;
  Future<void> open();
  Future<void> close();
  // TODO: be more specific?
  Future<void> writeCommand(String command);
  Stream<String> get readStream;
}
