import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/account/account_tokens_section.dart';
import 'package:reaprime/src/controllers/account_tokens_controller.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart'
    show CredentialStore;
import 'package:reaprime/src/services/account/proxy_token_service.dart';
import 'package:reaprime/src/services/account/proxy_token_store.dart';

class _FakeCredentialStore implements CredentialStore {
  final Map<String, String> _data = {};
  @override
  Future<String?> read({required String key}) async => _data[key];
  @override
  Future<void> write({required String key, required String value}) async =>
      _data[key] = value;
  @override
  Future<void> delete({required String key}) async => _data.remove(key);
}

void main() {
  late ProxyTokenService service;
  late AccountTokensController controller;

  setUp(() {
    service = ProxyTokenService();
    controller = AccountTokensController(
      tokenService: service,
      store: ProxyTokenStore(credentialStore: _FakeCredentialStore()),
    );
  });

  Widget harness() => MaterialApp(
        home: Scaffold(
          body: AccountTokensSection(controller: controller),
        ),
      );

  testWidgets('create -> show once -> list, then revoke', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.text('No tokens yet.'), findsOneWidget);

    // Create
    await tester.tap(find.byKey(const Key('create-token')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'laptop');
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Create'),
    ));
    await tester.pumpAndSettle();

    // Token is shown once, and it's a real registered token.
    final shown = tester.widget<SelectableText>(
      find.byKey(const Key('token-value')),
    );
    final tokenValue = shown.data!;
    expect(service.validate(tokenValue), isNotNull);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Listed
    expect(find.text('laptop'), findsOneWidget);
    expect(find.text('read'), findsOneWidget);

    // Revoke
    await tester.tap(find.byKey(const Key('revoke-laptop')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();

    expect(find.text('laptop'), findsNothing);
    expect(find.text('No tokens yet.'), findsOneWidget);
    expect(service.validate(tokenValue), isNull);
  });
}
