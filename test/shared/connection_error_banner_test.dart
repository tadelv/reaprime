import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/shared/connection_error_banner.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/fake_connection_manager.dart';

void main() {
  group('ConnectionErrorBanner', () {
    testWidgets('renders when status.error is set', (tester) async {
      final cm = FakeConnectionManager();
      cm.setError(ConnectionError(
        kind: ConnectionErrorKind.scaleConnectFailed,
        severity: ConnectionErrorSeverity.error,
        timestamp: DateTime.now().toUtc(),
        message: 'Scale connect failed.',
        suggestion: 'Wake the scale and try again.',
        deviceName: 'Decent Scale',
      ));

      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: ConnectionErrorBanner(connectionManager: cm),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Scale connect failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Decent Scale'), findsOneWidget);
    });

    testWidgets('hides when status.error is null', (tester) async {
      final cm = FakeConnectionManager();
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: ConnectionErrorBanner(connectionManager: cm),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ShadAlert), findsNothing);
    });

    testWidgets('Retry button dispatches a scan on press', (tester) async {
      final cm = FakeConnectionManager();
      cm.setError(ConnectionError(
        kind: ConnectionErrorKind.scaleConnectFailed,
        severity: ConnectionErrorSeverity.error,
        timestamp: DateTime.now().toUtc(),
        message: 'x',
        deviceName: 'Decent Scale',
      ));

      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: ConnectionErrorBanner(connectionManager: cm),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(cm.connectCalls, 1);
    });

    testWidgets(
      'adapterOff has no Retry button (text-only instruction)',
      (tester) async {
        final cm = FakeConnectionManager();
        cm.setError(ConnectionError(
          kind: ConnectionErrorKind.adapterOff,
          severity: ConnectionErrorSeverity.error,
          timestamp: DateTime.now().toUtc(),
          message: 'Bluetooth is off.',
        ));

        await tester.pumpWidget(
          ShadApp(
            home: Scaffold(
              body: ConnectionErrorBanner(connectionManager: cm),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Retry'), findsNothing);
      },
    );
  });
}
