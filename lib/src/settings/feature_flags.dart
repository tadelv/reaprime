/// Identifiers for all feature flags in the app.
///
/// Add new flags here as the first entry point. Each flag is a key
/// into [FeatureFlagService] (or [SettingsController.isFeatureFlagEnabled])
/// and corresponds to a persisted bool in SharedPreferences.
enum FeatureFlag {
  /// When enabled, the tablet defers `skipStep` on mixed weight/firmware
  /// exit steps to avoid racing firmware (issue #269).
  ///
  /// Default: **true** (opt-out — the fix is the new default behavior).
  stepExitArbiter,

  /// When enabled, replaces the endpoint-difference [FlowCalculator] +
  /// [MovingAverage] pipeline with a 1-D constant-velocity Kalman filter
  /// ([KalmanFlowEstimator]) that provides signed, low-lag flow estimates
  /// with disturbance rejection (issue #417).
  ///
  /// Default: **false** (opt-in — validation window for stop-timing risk).
  kalmanFlow,
}

/// Default values for each flag. Flags that ship as "on" default to true;
/// flags that ship as experimental default to false.
const Map<FeatureFlag, bool> defaultFeatureFlagValues = {
  FeatureFlag.stepExitArbiter: true,
  FeatureFlag.kalmanFlow: false,
};