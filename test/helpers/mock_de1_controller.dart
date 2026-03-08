import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:rxdart/subjects.dart';

/// A De1Controller subclass for testing ConnectionManager.
///
/// Records all [connectToDe1] calls and allows controlling the `de1` stream
/// and simulating connection failures.
class MockDe1Controller extends De1Controller {
  /// Every [De1Interface] passed to [connectToDe1].
  final List<De1Interface> connectCalls = [];

  /// When true, [connectToDe1] throws instead of succeeding.
  bool shouldFailConnect = false;

  /// The subject backing the overridden [de1] stream.
  /// Tests can call `de1Subject.add(someDe1)` to simulate connection changes.
  final BehaviorSubject<De1Interface?> de1Subject =
      BehaviorSubject.seeded(null);

  MockDe1Controller({required super.controller});

  @override
  Stream<De1Interface?> get de1 => de1Subject.stream;

  @override
  Future<void> connectToDe1(De1Interface de1Interface) async {
    connectCalls.add(de1Interface);
    if (shouldFailConnect) {
      throw Exception('MockDe1Controller: simulated connection failure');
    }
    // Don't call super — we don't want real connection logic in tests.
    // Instead, surface the device on the stream so listeners see it.
    de1Subject.add(de1Interface);
  }
}
