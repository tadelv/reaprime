import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:reaprime/src/services/telemetry/telemetry_service.dart';
import 'package:reaprime/src/services/telemetry/log_buffer.dart';
import 'package:reaprime/src/services/telemetry/telemetry_report_queue.dart';

/// Firebase Crashlytics implementation of TelemetryService
///
/// Wraps Firebase Crashlytics SDK with privacy-first defaults:
/// - Telemetry collection disabled by default (requires explicit consent)
/// - Rolling log buffer attached to all error reports for context
/// - Custom keys for session and device metadata
/// - Bounded async report queue to prevent blocking UI thread
class FirebaseCrashlyticsTelemetryService implements TelemetryService {
  final LogBuffer _logBuffer;
  late final TelemetryReportQueue _queue;

  /// Create a new Firebase Crashlytics telemetry service
  ///
  /// [logBuffer] - Rolling log buffer for attaching context to error reports
  FirebaseCrashlyticsTelemetryService(this._logBuffer) {
    _queue = TelemetryReportQueue(_sendReport);
  }

  @override
  Future<void> initialize() async {
    // PRIV-04: Disable collection by default until user consents
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);

    // TELE-04: Set up global error handlers to route through TelemetryService
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Internal method to actually send a report to Firebase
  ///
  /// This is called by the queue's async drain loop and performs the actual
  /// platform channel IPC to Firebase Crashlytics.
  Future<void> _sendReport(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
  }) async {
    // Attach current log buffer contents for context
    await FirebaseCrashlytics.instance.setCustomKey(
      'log_buffer',
      _logBuffer.getContents(),
    );

    // Record the error
    await FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      fatal: fatal,
    );
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
  }) async {
    // Enqueue the report for async processing
    // This returns quickly without blocking on platform channel calls
    _queue.enqueue(error, stackTrace, fatal: fatal);
  }

  @override
  Future<void> log(String message) async {
    // Log to both Firebase and local buffer
    await FirebaseCrashlytics.instance.log(message);
    _logBuffer.append(message);
  }

  @override
  Future<void> setCustomKey(String key, Object value) async {
    await FirebaseCrashlytics.instance.setCustomKey(key, value);
  }

  @override
  Future<void> setConsentEnabled(bool enabled) async {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
  }

  @override
  String getLogBuffer() {
    return _logBuffer.getContents();
  }
}
