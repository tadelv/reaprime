import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/account/proxy_token_service.dart';

void main() {
  test('mints a non-empty skin token that validates as the skin caller', () {
    final service = ProxyTokenService();

    expect(service.skinToken, isNotEmpty);
    final caller = service.validate(service.skinToken);
    expect(caller, isNotNull);
    expect(caller!.id, 'skin');
    expect(caller.scopes, contains(ProxyTokenService.scopeAccountProxy));
  });

  test('two instances mint different skin tokens', () {
    expect(ProxyTokenService().skinToken,
        isNot(ProxyTokenService().skinToken));
  });

  test('unknown tokens do not validate', () {
    final service = ProxyTokenService();
    expect(service.validate('nope'), isNull);
  });

  test('registers and revokes API-client tokens', () {
    final service = ProxyTokenService();
    service.registerToken(
      'tok-123',
      const ProxyCaller(
        id: 'api:laptop',
        scopes: {ProxyTokenService.scopeAccountProxy},
      ),
    );

    expect(service.validate('tok-123')!.id, 'api:laptop');

    service.revokeToken('tok-123');
    expect(service.validate('tok-123'), isNull);
  });

  test('the skin token cannot be revoked', () {
    final service = ProxyTokenService();
    service.revokeToken(service.skinToken);
    expect(service.validate(service.skinToken), isNotNull);
  });
}
