import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/presence_settings_page.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/mock_settings_service.dart';

void main() {
  late MockSettingsService mockService;
  late SettingsController controller;

  Widget buildPage() {
    return MaterialApp(
      home: ShadApp(home: PresenceSettingsPage(controller: controller)),
    );
  }

  setUp(() async {
    mockService = MockSettingsService();
    controller = SettingsController(mockService);
    await controller.loadSettings();
  });

  group('sleep timeout text field', () {
    testWidgets('enters an in-range value and commits it', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pump();

      final field = find.byType(TextFormField).first;
      await tester.enterText(field, '37');

      final setButton = find.text('Set');
      await tester.tap(setButton);
      await tester.pump();

      expect(controller.sleepTimeoutMinutes, 37);
    });

    testWidgets('enters a value above 240, normalizes to 240', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pump();

      final field = find.byType(TextFormField).first;
      await tester.enterText(field, '999');

      final setButton = find.text('Set');
      await tester.tap(setButton);
      await tester.pump();

      expect(controller.sleepTimeoutMinutes, 240);
      expect(find.text('240'), findsWidgets);
    });

    testWidgets('enters negative value, normalizes to 0', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pump();

      final field = find.byType(TextFormField).first;
      await tester.enterText(field, '-10');

      final setButton = find.text('Set');
      await tester.tap(setButton);
      await tester.pump();

      expect(controller.sleepTimeoutMinutes, 0);
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('empty text shows validation and is not persisted', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage());
      await tester.pump();

      final field = find.byType(TextFormField).first;
      await tester.enterText(field, '');

      final setButton = find.text('Set');
      await tester.tap(setButton);
      await tester.pump();

      expect(find.text('Enter a number of minutes'), findsOneWidget);
      expect(controller.sleepTimeoutMinutes, 30);
    });

    testWidgets('non-numeric text shows validation and is not persisted', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage());
      await tester.pump();

      final field = find.byType(TextFormField).first;
      await tester.enterText(field, 'abc');

      final setButton = find.text('Set');
      await tester.tap(setButton);
      await tester.pump();

      expect(find.text('Enter a number of minutes'), findsOneWidget);
      expect(controller.sleepTimeoutMinutes, 30);
    });

    testWidgets('arbitrary value like 37 is supported', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pump();

      final field = find.byType(TextFormField).first;
      await tester.enterText(field, '37');

      final setButton = find.text('Set');
      await tester.tap(setButton);
      await tester.pump();

      expect(controller.sleepTimeoutMinutes, 37);
      expect(find.text('37'), findsWidgets);
    });
  });
}
