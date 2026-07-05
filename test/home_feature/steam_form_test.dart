import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _wrap(Widget child) {
  return ShadApp(
    home: Scaffold(
      body: Material(child: child),
    ),
  );
}

void main() {
  group('SteamForm', () {
    testWidgets('renders stop-at-temperature controls when enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SteamForm(
            steamSettings: SteamFormSettings(
              steamEnabled: true,
              targetTemp: 150,
              targetDuration: 30,
              targetFlow: 1.0,
              stopAtTemperature: 65.0,
            ),
            apply: (settings) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stop at probe temperature'), findsOneWidget);
      expect(find.textContaining('Stop at: 65.0'), findsOneWidget);
    });

    testWidgets('hides preferred probe picker with one or zero probes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SteamForm(
            steamSettings: SteamFormSettings(
              steamEnabled: true,
              targetTemp: 150,
              targetDuration: 30,
              targetFlow: 1.0,
            ),
            probeOptions: const [
              SteamProbeOption(deviceId: 'probe-a', label: 'Probe A'),
            ],
            apply: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Preferred probe'), findsNothing);
    });

    testWidgets('shows preferred probe picker when multiple probes present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SteamForm(
            steamSettings: SteamFormSettings(
              steamEnabled: true,
              targetTemp: 150,
              targetDuration: 30,
              targetFlow: 1.0,
              preferredProbeId: 'probe-b',
            ),
            probeOptions: const [
              SteamProbeOption(deviceId: 'probe-a', label: 'Probe A'),
              SteamProbeOption(deviceId: 'probe-b', label: 'Probe B'),
            ],
            apply: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Preferred probe'), findsOneWidget);
      expect(find.text('Probe B'), findsOneWidget);
    });

    testWidgets('apply persists stopAtTemperature and preferred probe', (
      tester,
    ) async {
      SteamFormSettings? applied;
      await tester.pumpWidget(
        _wrap(
          SteamForm(
            steamSettings: SteamFormSettings(
              steamEnabled: true,
              targetTemp: 150,
              targetDuration: 30,
              targetFlow: 1.0,
              stopAtTemperature: 62.0,
              preferredProbeId: 'probe-a',
            ),
            probeOptions: const [
              SteamProbeOption(deviceId: 'probe-a', label: 'Probe A'),
              SteamProbeOption(deviceId: 'probe-b', label: 'Probe B'),
            ],
            apply: (settings) => applied = settings,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied, isNotNull);
      expect(applied!.stopAtTemperature, equals(62.0));
      expect(applied!.preferredProbeId, equals('probe-a'));
    });

    test('toSteamSettings binds workflow stopAtTemperature', () {
      final formSettings = SteamFormSettings(
        steamEnabled: true,
        targetTemp: 150,
        targetDuration: 30,
        targetFlow: 1.0,
        stopAtTemperature: 68.0,
      );

      final workflowSettings = formSettings.toSteamSettings();

      expect(workflowSettings.stopAtTemperature, equals(68.0));
      expect(workflowSettings.targetTemperature, equals(150));
    });
  });
}
