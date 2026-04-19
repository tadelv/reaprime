import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/rxdart.dart';

/// A ScaleController subclass for testing ConnectionManager.
///
/// Records all [connectToScale] calls and allows controlling the
/// `connectionState` stream and simulating connection failures.
class MockScaleController extends ScaleController {
  /// Every [Scale] passed to [connectToScale].
  final List<Scale> connectCalls = [];

  /// When true, [connectToScale] throws a generic [Exception].
  bool shouldFailConnect = false;

  /// When non-null, [connectToScale] throws this exact object. Takes
  /// precedence over [shouldFailConnect]. Useful for exercising
  /// typed-exception branches (e.g. `FlutterBluePlusException`).
  Object? failNextConnectWith;

  /// The subject backing the overridden [connectionState] stream.
  /// Tests can call `connectionStateSubject.add(...)` to simulate changes.
  final BehaviorSubject<ConnectionState> connectionStateSubject =
      BehaviorSubject.seeded(ConnectionState.discovered);

  MockScaleController();

  @override
  Stream<ConnectionState> get connectionState =>
      connectionStateSubject.stream;

  @override
  Future<void> connectToScale(Scale scale) async {
    connectCalls.add(scale);
    if (failNextConnectWith != null) {
      final err = failNextConnectWith!;
      failNextConnectWith = null;
      throw err;
    }
    if (shouldFailConnect) {
      throw Exception('MockScaleController: simulated connection failure');
    }
    // Don't call super — we don't want real connection logic in tests.
    // Instead, emit connected state so listeners see the change.
    connectionStateSubject.add(ConnectionState.connected);
  }
}
