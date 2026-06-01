import 'dart:async';

import 'package:reaprime/src/models/device/device.dart';

/// Simple interface for sending and receiving bytes.
/// This is the minimal abstraction needed for DE1 communication.
abstract class DataTransport {
  String get id;
  String get name;

  Stream<ConnectionState> get connectionState;
  /// Connect to the transport
  Future<void> connect();

  /// Disconnect from the transport
  Future<void> disconnect();

  /// End-of-life cleanup. Release native resources, close subjects,
  /// cancel subscriptions. Safe to call more than once. Re-using this
  /// transport after dispose is not supported.
  Future<void> dispose();
}

