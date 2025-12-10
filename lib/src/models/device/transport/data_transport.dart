import 'dart:async';

/// Simple interface for sending and receiving bytes.
/// This is the minimal abstraction needed for DE1 communication.
abstract class DataTransport {
  String get id;
  String get name;

  Stream<bool> get connectionState;
  /// Connect to the transport
  Future<void> connect();

  /// Disconnect from the transport
  Future<void> disconnect();
}

