import 'dart:async';

import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/rxdart.dart';

import 'mock_de1_controller.dart';
import 'mock_device_scanner.dart';
import 'mock_scale_controller.dart';
import 'mock_settings_service.dart';

/// A [ConnectionManager] subclass that gives tests direct control over the
/// status stream and records `connect()` calls. Builds its own minimal
/// collaborators so tests only need:
///
/// ```dart
/// final cm = FakeConnectionManager();
/// cm.setError(ConnectionError(...));
/// ```
///
/// Widgets that consume `ConnectionManager.status` + `connect()` can be
/// driven directly by this fake.
class FakeConnectionManager extends ConnectionManager {
  final BehaviorSubject<ConnectionStatus> _statusOverride =
      BehaviorSubject.seeded(const ConnectionStatus());

  int connectCalls = 0;
  bool _scaleOnlyLastCall = false;
  bool get scaleOnlyLastCall => _scaleOnlyLastCall;

  FakeConnectionManager._({
    required super.deviceScanner,
    required super.de1Controller,
    required super.scaleController,
    required super.settingsController,
  });

  factory FakeConnectionManager() {
    final scanner = MockDeviceScanner();
    final de1 = MockDe1Controller(controller: DeviceController([]));
    final scale = MockScaleController();
    final settings = SettingsController(MockSettingsService());
    return FakeConnectionManager._(
      deviceScanner: scanner,
      de1Controller: de1,
      scaleController: scale,
      settingsController: settings,
    );
  }

  @override
  Stream<ConnectionStatus> get status => _statusOverride.stream;

  @override
  ConnectionStatus get currentStatus => _statusOverride.value;

  void emitStatus(ConnectionStatus status) => _statusOverride.add(status);

  /// Sets or clears the `error` field on the current status. Pass `null`
  /// to clear.
  void setError(ConnectionError? err) {
    _statusOverride.add(
      _statusOverride.value.copyWith(error: () => err),
    );
  }

  @override
  Future<void> connect({bool scaleOnly = false}) async {
    connectCalls += 1;
    _scaleOnlyLastCall = scaleOnly;
  }

  @override
  void dispose() {
    _statusOverride.close();
    super.dispose();
  }
}
