import 'dart:async';
import 'package:logging/logging.dart';
import 'package:reaprime/src/services/telemetry/telemetry_service.dart';

/// Lightweight cold-boot timing instrumentation.
///
/// [start] is called once at the top of `main()`. [mark] records a milestone
/// (logged on every platform, so it shows up in the on-device log + the
/// m50mini `/api/v1/logs` dump). [complete] is called once when the first
/// webview is up and emits all collected milestone durations as a single
/// `cold_boot` Firebase Performance trace.
///
/// A live trace can't span the whole boot — Firebase isn't initialized at
/// `main()` start — so each milestone's elapsed-since-start is recorded as a
/// trace *metric*, with `total_ms` as the final elapsed.
class BootTiming {
  static final Stopwatch _sw = Stopwatch();
  static final Logger _log = Logger('BootTiming');
  static final Map<String, int> _marks = {};
  static int _lastMs = 0;
  static bool _completed = false;

  /// Telemetry sink for the `cold_boot` trace. Wired in `main()` once the
  /// telemetry service exists. Left null in tests / unsupported platforms.
  static TelemetryService? telemetry;

  static void start() {
    _sw
      ..reset()
      ..start();
    _lastMs = 0;
    _marks.clear();
    _completed = false;
  }

  static void mark(String label) {
    if (!_sw.isRunning) return;
    final now = _sw.elapsedMilliseconds;
    _log.info('[BOOT] $label: ${now}ms (Δ${now - _lastMs}ms)');
    _marks[_metricKey(label)] = now;
    _lastMs = now;
  }

  /// One-shot — emits the `cold_boot` Performance trace. Safe to call more
  /// than once (only the first call records).
  static void complete() {
    if (_completed || !_sw.isRunning) return;
    _completed = true;
    final total = _sw.elapsedMilliseconds;
    _sw.stop();
    _log.info('[BOOT] complete: total ${total}ms');
    final metrics = Map<String, int>.from(_marks)..['total_ms'] = total;
    final t = telemetry;
    if (t != null) {
      unawaited(
        t
            .recordTrace('cold_boot', metrics)
            .catchError(
              (Object e) => _log.warning('boot trace failed: $e'),
            ),
      );
    }
  }

  /// Firebase Performance metric name: <=32 chars, alnum + underscore.
  static String _metricKey(String label) {
    var k = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    k = k.replaceAll(RegExp(r'^_+|_+$'), '');
    if (!k.endsWith('_ms')) k = '${k}_ms';
    if (k.length > 32) k = k.substring(0, 32);
    return k;
  }
}
