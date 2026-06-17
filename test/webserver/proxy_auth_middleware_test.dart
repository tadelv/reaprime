import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/account/proxy_token_service.dart';
import 'package:reaprime/src/services/webserver/proxy_auth_middleware.dart';
import 'package:shelf/shelf.dart';

void main() {
  late ProxyTokenService tokens;
  late Handler handler;
  late Request? seenByInner;

  setUp(() {
    tokens = ProxyTokenService(skinToken: 'skin-token');
    seenByInner = null;
    Response inner(Request request) {
      seenByInner = request;
      return Response.ok('inner');
    }

    handler = const Pipeline()
        .addMiddleware(proxyAuthMiddleware(tokens))
        .addHandler(inner);
  });

  Request request(
    String method,
    String path, {
    Map<String, String> headers = const {},
  }) => Request(method, Uri.parse('http://localhost$path'), headers: headers);

  Request get(String path, {Map<String, String> headers = const {}}) =>
      request('GET', path, headers: headers);

  test('passes non-proxy paths through without auth', () async {
    final response = await handler(get('/api/v1/shots'));
    expect(response.statusCode, 200);
    expect(seenByInner, isNotNull);
    expect(proxyCallerOf(seenByInner!), isNull);
  });

  test('rejects a proxy request with no Authorization (401)', () async {
    final response = await handler(get('/api/v1/account/proxy/support/api/sn'));
    expect(response.statusCode, 401);
    expect(seenByInner, isNull);
  });

  test('rejects a proxy request with an unknown token (401)', () async {
    final response = await handler(
      get(
        '/api/v1/account/proxy/support/api/sn',
        headers: {'authorization': 'Bearer wrong'},
      ),
    );
    expect(response.statusCode, 401);
  });

  test('rejects a known token that lacks the required scope (403)', () async {
    tokens.registerToken(
      'scopeless',
      const ProxyCaller(id: 'api:weak', scopes: {}),
    );
    final response = await handler(
      get(
        '/api/v1/account/proxy/support/api/sn',
        headers: {'authorization': 'Bearer scopeless'},
      ),
    );
    expect(response.statusCode, 403);
    final body = jsonDecode(await response.readAsString());
    expect(body['error'], contains('account:proxy'));
  });

  test('admits the skin token and tags the caller', () async {
    final response = await handler(
      get(
        '/api/v1/account/proxy/support/api/sn',
        headers: {'authorization': 'Bearer skin-token'},
      ),
    );
    expect(response.statusCode, 200);
    expect(seenByInner, isNotNull);
    final caller = proxyCallerOf(seenByInner!);
    expect(caller, isNotNull);
    expect(caller!.id, 'skin');
  });

  test('rejects POST with a read-only token (403)', () async {
    final response = await handler(
      request(
        'POST',
        '/api/v1/account/proxy/support/api/email',
        headers: {'authorization': 'Bearer skin-token'},
      ),
    );

    expect(response.statusCode, 403);
    expect(seenByInner, isNull);
    final body = jsonDecode(await response.readAsString());
    expect(body['error'], contains(ProxyTokenService.scopeAccountProxyWrite));
  });

  test('admits POST with a write-scoped token and tags the caller', () async {
    tokens.registerToken(
      'writer',
      const ProxyCaller(
        id: 'api:writer',
        scopes: {ProxyTokenService.scopeAccountProxyWrite},
      ),
    );

    final response = await handler(
      request(
        'POST',
        '/api/v1/account/proxy/support/api/email',
        headers: {'authorization': 'Bearer writer'},
      ),
    );

    expect(response.statusCode, 200);
    final caller = proxyCallerOf(seenByInner!);
    expect(caller, isNotNull);
    expect(caller!.id, 'api:writer');
  });

  test('admits PUT with a write-scoped token and tags the caller', () async {
    tokens.registerToken(
      'writer',
      const ProxyCaller(
        id: 'api:writer',
        scopes: {ProxyTokenService.scopeAccountProxyWrite},
      ),
    );

    final response = await handler(
      request(
        'PUT',
        '/api/v1/account/proxy/support/api/profile',
        headers: {'authorization': 'Bearer writer'},
      ),
    );

    expect(response.statusCode, 200);
    final caller = proxyCallerOf(seenByInner!);
    expect(caller, isNotNull);
    expect(caller!.id, 'api:writer');
  });

  test('lets CORS preflight through unauthenticated', () async {
    final response = await handler(
      Request('OPTIONS', Uri.parse('http://localhost/api/v1/account/proxy/x')),
    );
    expect(response.statusCode, 200);
    expect(seenByInner, isNotNull);
  });
}
