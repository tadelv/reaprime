import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/errors.dart';

const _webUiStorageLoggerName = 'WebUIStorage';
const _skinAlreadyExistsPrefix = 'Skin already exists';
const _benignNetworkErrorPrefixes = [
  'Exception: Failed to fetch GitHub release:',
  'Exception: Failed to download:',
];

/// Loggers whose `WARNING+` records describe HTTP fetches we know can
/// transiently fail in the field (DNS, offline, GitHub rate-limit). When
/// the attached `error` is a transient network exception, the record is
/// dropped from telemetry forwarding regardless of message.
///
/// Intentionally narrow — adding a logger here also opts it in to
/// `_isTransientNetworkError` matching, so do not add loggers that should
/// surface their own SocketExceptions (e.g. BLE transports).
const _httpFetcherLoggers = <String>{
  _webUiStorageLoggerName,
  'AndroidUpdater',
};

/// Returns `false` for log records that match a known telemetry-noise pattern
/// — caller should skip forwarding these to Crashlytics.
///
/// Caller is expected to gate on `record.level >= Level.WARNING` first;
/// records below WARNING never reach Crashlytics today, so this predicate
/// only describes WARNING+ records.
bool shouldForwardToTelemetry(LogRecord record) {
  // Drop typed transient exceptions regardless of source logger. These
  // are part of the codebase's normal error model — connection drops,
  // bounded MMR-read timeouts — not crash signals.
  if (record.error is DeviceNotConnectedException) return false;
  if (record.error is MmrTimeoutException) return false;

  if (record.loggerName == _webUiStorageLoggerName &&
      record.message.startsWith(_skinAlreadyExistsPrefix)) {
    return false;
  }

  if (_httpFetcherLoggers.contains(record.loggerName) &&
      _isTransientNetworkError(record.error)) {
    return false;
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
