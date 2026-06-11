import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/launcher/widgets/connect_device_hero_card.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('ConnectDeviceHeroCard fires onScan when tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: ConnectDeviceHeroCard(onScan: () => tapped++),
        ),
      ),
    );

    expect(find.text('Connect your machine'), findsOneWidget);

    await tester.tap(find.text('Scan for devices'));
    await tester.pump();

    expect(tapped, 1);
  });
}
