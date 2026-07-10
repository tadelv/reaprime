/// A 1-D constant-velocity Kalman filter estimating [weight, flow] from
/// noisy scale weight measurements.
///
/// Replaces both [FlowCalculator] (endpoint differencing) and [MovingAverage]
/// (count-based smoothing) with a single estimator that has online
/// self-adaptation baked in.
///
/// ## Design
///
/// - **Adaptive measurement noise `R`** — tracked online from innovation
///   (residual) variance. Clean signal → small `R` → snappy, low-lag flow.
///   Disturbance (tap, knock, drip splat) → residuals spike → `R` grows →
///   filter distrusts the transient → flow stays smooth.
/// - **Fixed process noise `Q`** from flow physics (0–10 g/s, bounded ramp
///   rate). We adapt trust in the sensor, not the physics model.
/// - **Variable `dt`** in every predict step — fixes the count-based window
///   bug of the old [MovingAverage].
/// - **Signed flow** — no `.abs()` (un-breaks the cup-removal branch in
///   [ShotSequencer._refineStoppingYield]).
/// - **Hard re-init at tare** via [reset] — re-seeds weight to current, flow
///   to 0, covariance high (replaces the `_flowSettleUntil` suppress-window
///   hack).
///
/// ## Multi-scale
///
/// Adaptive `R` auto-calibrates its baseline to whatever scale's noise floor
/// is connected (no per-scale `R` table). Variable-`dt` handles a slower
/// scale's larger intervals. Two mechanisms, two axes (noise vs rate).
class KalmanFlowEstimator {
  // -- State vector: [weight, flow] --

  double _weight;
  double _flow;

  // -- Covariance matrix P (2×2, symmetric) --

  double _p11, _p12, _p21, _p22;

  // -- Timestamp of the last sample --

  DateTime? _lastTimestamp;

  // -- Adaptive measurement noise --

  double _r;

  // -- Fixed process noise intensity (continuous-time acceleration variance) --

  final double _q;

  // -- R adaptation constants --

  /// EMA smoothing factor for the innovation-variance tracker.
  static const double _alpha = 0.1;

  /// Floor for R — prevents filter divergence when the scale is dead-quiet.
  static const double _rMin = 0.01;

  /// Ceiling for R — balances disturbance rejection against step-response
  /// speed. High enough to attenuate taps/knocks, low enough that a genuine
  /// level change (placing a cup) can still be tracked.
  static const double _rMax = 50.0;

  /// Initial measurement noise (before any innovation history).
  static const double _initialR = 10.0;

  /// Initial covariance diagonal — large so the filter converges quickly from
  /// a cold start.
  static const double _initialCovariance = 100.0;

  /// Minimum covariance diagonal — prevents the filter from becoming
  /// overconfident and unable to track genuine level changes (e.g. placing
  /// a cup on the scale).
  static const double _pMin = 0.1;

  /// Creates a Kalman flow estimator seeded with [initialWeight].
  ///
  /// [processNoiseIntensity] is the continuous-time acceleration variance `q`.
  /// Default 2.0 ≈ ±1.4 g/s² RMS, matching typical espresso flow change
  /// rates (ramp from 0→8 g/s over several seconds).
  KalmanFlowEstimator({
    required double initialWeight,
    double processNoiseIntensity = 2.0,
  })  : _weight = initialWeight,
        _flow = 0.0,
        _p11 = _initialCovariance,
        _p12 = 0.0,
        _p21 = 0.0,
        _p22 = _initialCovariance,
        _q = processNoiseIntensity,
        _r = _initialR;

  /// The current filtered weight estimate.
  double get weight => _weight;

  /// The current flow estimate (signed, g/s).
  double get flow => _flow;

  /// Feed a new raw weight sample and return the updated (weight, flow)
  /// estimates.
  ///
  /// The first call initialises the internal timestamp without running a
  /// filter update — only the state is seeded to [rawWeight]. Subsequent
  /// calls use the actual inter-sample `dt` for the predict step.
  (double weight, double flow) addSample(DateTime timestamp, double rawWeight) {
    if (_lastTimestamp == null) {
      _lastTimestamp = timestamp;
      _weight = rawWeight;
      return (_weight, _flow);
    }

    final dtMs = timestamp.difference(_lastTimestamp!).inMilliseconds;
    _lastTimestamp = timestamp;

    // Guard against zero or negative dt (e.g. BLE re-transmits).
    if (dtMs <= 0) {
      return (_weight, _flow);
    }

    final dt = dtMs / 1000.0; // seconds

    // ── Predict ──────────────────────────────────────────────────────
    //
    // State transition (constant velocity):
    //   x_pred = F @ x
    //   where F = [[1, dt],
    //              [0, 1]]

    final predWeight = _weight + _flow * dt;
    final predFlow = _flow;

    // P_pred = F @ P @ F^T + Q
    //
    // F @ P = [[p11 + dt·p21,  p12 + dt·p22],
    //          [p21,           p22]]
    final fp11 = _p11 + dt * _p21;
    final fp12 = _p12 + dt * _p22;
    final fp21 = _p21;
    final fp22 = _p22;

    // (F@P) @ F^T = [[fp11 + fp12·dt,  fp12],
    //                [fp21 + fp22·dt,  fp22]]
    final pp11 = fp11 + fp12 * dt;
    final pp12 = fp12;
    final pp21 = fp21 + fp22 * dt;
    final pp22 = fp22;

    // Q = q · [[dt³/3,  dt²/2],
    //          [dt²/2,  dt   ]]
    // (discrete white-noise acceleration model)
    final dt2 = dt * dt;
    final q11 = _q * dt2 * dt / 3.0;
    final q12 = _q * dt2 / 2.0;
    final q22 = _q * dt;

    final predP11 = pp11 + q11;
    final predP12 = pp12 + q12;
    final predP21 = pp21 + q12;
    final predP22 = pp22 + q22;

    // ── Update ───────────────────────────────────────────────────────
    //
    // Measurement model:
    //   z = rawWeight  (we only observe weight)
    //   H = [1, 0]

    final innovation = rawWeight - predWeight;

    // Adaptive R — EMA of squared innovation, with the innovation clipped
    // so a single large step (placing a cup) doesn't inflate R excessively.
    // Sustained large innovations indicate a genuine level/rate change that
    // the filter should track, not a transient to reject.
    final clipped = innovation.clamp(-5.0, 5.0);
    _r = _alpha * clipped * clipped + (1.0 - _alpha) * _r;
    _r = _r.clamp(_rMin, _rMax);

    // Innovation covariance: S = H @ P_pred @ H^T + R = predP11 + R
    final s = predP11 + _r;

    // Kalman gain: K = P_pred @ H^T / S = [predP11, predP21]^T / S
    final k1 = predP11 / s;
    final k2 = predP21 / s;

    // State update: x = x_pred + K · innovation
    _weight = predWeight + k1 * innovation;
    _flow = predFlow + k2 * innovation;

    // Covariance update: P = (I - K@H) @ P_pred
    //   I - K@H = [[1-k1, 0],
    //              [-k2,  1]]
    _p11 = (1.0 - k1) * predP11;
    _p12 = (1.0 - k1) * predP12;
    _p21 = predP21 - k2 * predP11;
    _p22 = predP22 - k2 * predP12;

    // Floor P to prevent overconfidence.
    if (_p11 < _pMin) _p11 = _pMin;
    if (_p22 < _pMin) _p22 = _pMin;

    return (_weight, _flow);
  }

  /// Hard re-initialisation — call at tare.
  ///
  /// Resets weight to [initialWeight], flow to 0, and covariance to high
  /// (the filter quickly re-converges from the new baseline). Also resets
  /// the adaptive-R tracker so a post-tare spike doesn't inherit a stale
  /// noise estimate.
  void reset(double initialWeight) {
    _weight = initialWeight;
    _flow = 0.0;
    _p11 = _initialCovariance;
    _p12 = 0.0;
    _p21 = 0.0;
    _p22 = _initialCovariance;
    _lastTimestamp = null;
    _r = _initialR;
  }
}
