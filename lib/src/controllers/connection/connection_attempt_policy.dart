class ConnectionAttemptPolicy {
  final bool directRememberedMachine;
  final bool connectPreferredDuringScan;
  final bool stopScanAfterPreferredConnect;

  const ConnectionAttemptPolicy._({
    required this.directRememberedMachine,
    required this.connectPreferredDuringScan,
    required this.stopScanAfterPreferredConnect,
  });

  static const automatic = ConnectionAttemptPolicy._(
    directRememberedMachine: true,
    connectPreferredDuringScan: true,
    stopScanAfterPreferredConnect: true,
  );

  static const explicitScan = ConnectionAttemptPolicy._(
    directRememberedMachine: false,
    connectPreferredDuringScan: false,
    stopScanAfterPreferredConnect: false,
  );

  static const scaleRecovery = ConnectionAttemptPolicy._(
    directRememberedMachine: false,
    connectPreferredDuringScan: true,
    stopScanAfterPreferredConnect: false,
  );
}
