import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:reaprime/src/services/account/decent_account_service.dart';
import 'package:reaprime/src/services/account/decent_proxy_service.dart';
import 'package:reaprime/src/services/account/proxy_token_service.dart';
import 'package:reaprime/src/services/webserver/proxy_auth_middleware.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:shelf_plus/shelf_plus.dart';

class FakeCredentialStore implements CredentialStore {
  final Map<String, String> _values = {};
  @override
  Future<String?> read({required String key}) async => _values[key];
  @override
  Future<void> write({required String key, required String value}) async =>
      _values[key] = value;
  @override
  Future<void> delete({required String key}) async => _values.remove(key);
}

void main() {
  late FakeCredentialStore store;
  late ProxyTokenService tokens;
  late Handler handler;
  late http.Request? upstream;

  setUp(() {
    store = FakeCredentialStore();
    tokens = ProxyTokenService(skinToken: 'skin-token');
    upstream = null;

    final proxy = DecentProxyService(
      httpClient: http_testing.MockClient((request) async {
        upstream = request;
        return http.Response('SN001\nSN002', 200);
      }),
      credentialStore: store,
    );

    final app = Router().plus;
    AccountProxyHandler(proxy: proxy).addRoutes(app);
    handler = const Pipeline()
        .addMiddleware(proxyAuthMiddleware(tokens))
        .addHandler(app.call);
  });

  Future<void> linkAccount() async {
    await store.write(key: 'email', value: 'user@example.com');
    await store.write(key: 'password', value: 'cryptpw_abc123');
  }

  Future<Response> get(String path, {String? token}) async {
    return handler(Request(
      'GET',
      Uri.parse('http://localhost$path'),
      headers: token == null ? {} : {'authorization': 'Bearer $token'},
    ));
  }

  test('unauthenticated proxy request is rejected (401)', () async {
    final response = await get('/api/v1/account/proxy/support/api/sn');
    expect(response.statusCode, 401);
    expect(upstream, isNull);
  });

  test('authenticated but unlinked returns 401', () async {
    final response =
        await get('/api/v1/account/proxy/support/api/sn', token: 'skin-token');
    expect(response.statusCode, 401);
    final body = jsonDecode(await response.readAsString());
    expect(body['error'], contains('not linked'));
    expect(upstream, isNull);
  });

  test('authenticated + linked forwards with Basic auth and relays body',
      () async {
    await linkAccount();
    final response =
        await get('/api/v1/account/proxy/support/api/sn', token: 'skin-token');

    expect(response.statusCode, 200);
    expect(await response.readAsString(), 'SN001\nSN002');

    final expected =
        'Basic ${base64Encode(utf8.encode('user@example.com:cryptpw_abc123'))}';
    expect(upstream!.headers['authorization'], expected);
    expect(upstream!.url.toString(),
        'https://decentespresso.com/support/api/sn');
  });

  test('a path outside the allowed prefix returns 403', () async {
    await linkAccount();
    final response =
        await get('/api/v1/account/proxy/admin/wipe', token: 'skin-token');
    expect(response.statusCode, 403);
    expect(upstream, isNull);
  });

  test('forwards query parameters to upstream', () async {
    await linkAccount();
    await get(
      '/api/v1/account/proxy/support/api/email?subject=hi&body=b',
      token: 'skin-token',
    );
    expect(upstream!.url.queryParameters['subject'], 'hi');
    expect(upstream!.url.queryParameters['body'], 'b');
  });
}
