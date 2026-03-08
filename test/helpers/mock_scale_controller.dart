import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/rxdart.dart';

/// A ScaleController subclass for testing ConnectionManager.
///
/// Records all [connectToScale] calls and allows controlling the
/// `connectionState` stream and simulating connection failures.
///
/// The constructor overrides the parent's auto-connect device-stream listener
/// by immediately cancelling it via [dispose], then re-seeding a clean
/// connectionState subject. This prevents unwanted side effects in tests.
class MockScaleController extends ScaleController {
  /// Every [Scale] passed to [connectToScale].
  final List<Scale> connectCalls = [];

  /// When true, [connectToScale] throws instead of succeeding.
  bool shouldFailConnect = false;

  /// The subject backing the overridden [connectionState] stream.
  /// Tests can call `connectionStateSubject.add(...)` to simulate changes.
  final BehaviorSubject<ConnectionState> connectionStateSubject =
      BehaviorSubject.seeded(ConnectionState.discovered);

  MockScaleController({required super.controller}) {
    // Cancel the auto-connect listener that the parent constructor sets up,
    // so it doesn't fire during tests and cause unexpected connectToScale calls.
    dispose();
  }

  @override
  Stream<ConnectionState> get connectionState =>
      connectionStateSubject.stream;

  @override
  Future<void> connectToScale(Scale scale) async {
    connectCalls.add(scale);
    if (shouldFailConnect) {
      throw Exception('MockScaleController: simulated connection failure');
    }
    // Don't call super — we don't want real connection logic in tests.
    // Instead, emit connected state so listeners see the change.
    connectionStateSubject.add(ConnectionState.connected);
  }
}
