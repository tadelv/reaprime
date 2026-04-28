import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/services/telemetry/telemetry_forwarder_filter.dart';

LogRecord _record(
  Level level,
  String loggerName,
  String message, [
  Object? error,
  StackTrace? stackTrace,
]) {
  return LogRecord(level, message, loggerName, error, stackTrace);
}

void main() {
  group('shouldForwardToTelemetry', () {
    group('drops noise from WebUIStorage', () {
      test('"Skin already exists: ..." WARNING is dropped', () {
        final record = _record(
          Level.WARNING,
          'WebUIStorage',
          'Skin already exists: streamline_project-main, overwriting…',
        );
        expect(shouldForwardToTelemetry(record), isFalse);
      });

      test('SocketException at SEVERE is dropped', () {
        final record = _record(
          Level.SEVERE,
          'WebUIStorage',
          'Failed to install WebUI from URL: https://example.com/skin.zip',
          const SocketException('Failed host lookup: example.com'),
        );
        expect(shouldForwardToTelemetry(record), isFalse);
      });

      test('TimeoutException at SEVERE is dropped', () {
        final record = _record(
          Level.SEVERE,
          'WebUIStorage',
          'Failed to install WebUI from URL: https://example.com/skin.zip',
          TimeoutException('http get'),
        );
        expect(shouldForwardToTelemetry(record), isFalse);
      });

      test('HttpException at SEVERE is dropped', () {
        final record = _record(
          Level.SEVERE,
          'WebUIStorage',
          'Failed to install WebUI from URL: https://example.com/skin.zip',
          const HttpException('connection closed'),
        );
        expect(shouldForwardToTelemetry(record), isFalse);
      });

      test('Exception("Failed to fetch GitHub release: 403") is dropped', () {
        final record = _record(
          Level.SEVERE,
          'WebUIStorage',
          'GitHub release install failed',
          Exception('Failed to fetch GitHub release: 403'),
        );
        expect(shouldForwardToTelemetry(record), isFalse);
      });

      test('Exception("Failed to download: 404") is dropped', () {
        final record = _record(
          Level.SEVERE,
          'WebUIStorage',
          'Skin install failed',
          Exception('Failed to download: 404'),
        );
        expect(shouldForwardToTelemetry(record), isFalse);
      });
    });

    group('keeps real WebUIStorage problems', () {
      test('StateError at SEVERE is kept (real bug)', () {
        final record = _record(
          Level.SEVERE,
          'WebUIStorage',
          'Skin install failed',
          StateError('zip corrupt'),
        );
        expect(shouldForwardToTelemetry(record), isTrue);
      });

      test('Unrelated WARNING message is kept', () {
        final record = _record(
          Level.WARNING,
          'WebUIStorage',
          'Manifest parse failed: missing required field',
        );
        expect(shouldForwardToTelemetry(record), isTrue);
      });
    });

    group('does not affect other loggers', () {
      test('SocketException from BleTransport is kept', () {
        final record = _record(
          Level.SEVERE,
          'BleTransport',
          'connection failed',
          const SocketException('Connection refused'),
        );
        expect(shouldForwardToTelemetry(record), isTrue);
      });

      test(
        '"Skin already exists" emitted by a different logger is kept',
        () {
          final record = _record(
            Level.WARNING,
            'SomeOtherLogger',
            'Skin already exists: foo',
          );
          expect(shouldForwardToTelemetry(record), isTrue);
        },
      );
    });
  });
}
