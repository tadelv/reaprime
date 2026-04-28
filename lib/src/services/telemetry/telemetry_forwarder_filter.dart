import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

const _webUiStorageLoggerName = 'WebUIStorage';
const _skinAlreadyExistsPrefix = 'Skin already exists';
const _benignNetworkErrorPrefixes = [
  'Exception: Failed to fetch GitHub release:',
  'Exception: Failed to download:',
];

/// Returns `false` for log records that match a known telemetry-noise pattern
/// — caller should skip forwarding these to Crashlytics.
///
/// Caller is expected to gate on `record.level >= Level.WARNING` first;
/// records below WARNING never reach Crashlytics today, so this predicate
/// only describes WARNING+ records.
bool shouldForwardToTelemetry(LogRecord record) {
  if (record.loggerName == _webUiStorageLoggerName) {
    if (record.message.startsWith(_skinAlreadyExistsPrefix)) return false;
    if (_isTransientNetworkError(record.error)) return false;
  }
  return true;
}

bool _isTransientNetworkError(Object? error) {
  if (error == null) return false;
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  if (error is HttpException) return true;
  // package:http throws ClientException; matched by name to avoid an import
  // dependency from the telemetry layer.
  if (error.runtimeType.toString() == 'ClientException') return true;
  final asString = error.toString();
  for (final prefix in _benignNetworkErrorPrefixes) {
    if (asString.startsWith(prefix)) return true;
  }
  return false;
}
