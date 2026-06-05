import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:logging/logging.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart';
import 'package:reaprime/src/services/account/decent_proxy_service.dart';

class FakeCredentialStore implements CredentialStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}

void main() {
  late FakeCredentialStore store;

  setUp(() {
    store = FakeCredentialStore();
  });

  Future<void> linkAccount() async {
    await store.write(key: 'email', value: 'user@example.com');
    await store.write(key: 'password', value: 'cryptpw_abc123');
  }

  DecentProxyService buildService(
    http_testing.MockClientHandler handler, {
    String baseUrl = 'https://decentespresso.com',
  }) {
    return DecentProxyService(
      httpClient: http_testing.MockClient(handler),
      credentialStore: store,
      baseUrl: baseUrl,
    );
  }

  test('throws when no account is linked', () async {
    final service = buildService((request) async {
      fail('must not call upstream when not linked: ${request.url}');
    });

    expect(
      () => service.proxyGet(callerId: 'skin', path: 'support/api/sn'),
      throwsA(isA<DecentAccountNotLinkedException>()),
    );
  });

  test('attaches Basic auth and relays the upstream body + status', () async {
    await linkAccount();
    late http.Request captured;
    final service = buildService((request) async {
      captured = request;
      return http.Response('SN001\nSN002', 200);
    });

    final result = await service.proxyGet(
      callerId: 'skin',
      path: 'support/api/sn',
    );

    expect(result.statusCode, 200);
    expect(result.body, 'SN001\nSN002');

    // Credentials are attached server-side as Basic auth.
    final expected =
        'Basic ${base64Encode(utf8.encode('user@example.com:cryptpw_abc123'))}';
    expect(captured.headers['authorization'], expected);
    expect(
      captured.url.toString(),
      'https://decentespresso.com/support/api/sn',
    );
  });

  test('never leaks credentials into the returned response', () async {
    await linkAccount();
    final service = buildService((request) async {
      return http.Response('ok', 200);
    });

    final result = await service.proxyGet(
      callerId: 'skin',
      path: 'support/api/sn',
    );

    final serialized = '${result.body} ${jsonEncode(result.headers)}';
    expect(serialized.contains('cryptpw_abc123'), isFalse);
    expect(serialized.toLowerCase().contains('authorization'), isFalse);
  });

  test('relays upstream error status verbatim', () async {
    await linkAccount();
    final service = buildService((request) async {
      return http.Response('upstream boom', 503);
    });

    final result = await service.proxyGet(
      callerId: 'api:tok',
      path: 'support/api/sn',
    );

    expect(result.statusCode, 503);
    expect(result.body, 'upstream boom');
  });

  test('strips sensitive response headers but keeps content-type', () async {
    await linkAccount();
    final service = buildService((request) async {
      return http.Response(
        '{}',
        200,
        headers: {
          'content-type': 'application/json',
          'set-cookie': 'session=secret',
          'www-authenticate': 'Basic realm="x"',
          'content-encoding': 'gzip',
        },
      );
    });

    final result = await service.proxyGet(
      callerId: 'skin',
      path: 'support/api/sn',
    );

    expect(result.headers['content-type'], 'application/json');
    expect(result.headers.containsKey('set-cookie'), isFalse);
    expect(result.headers.containsKey('www-authenticate'), isFalse);
    // Body is already decoded — relaying transfer/length headers would corrupt it.
    expect(result.headers.containsKey('content-encoding'), isFalse);
    expect(result.headers.containsKey('content-length'), isFalse);
  });

  test('rejects a path outside the allowed prefix', () async {
    await linkAccount();
    final service = buildService((request) async {
      fail('must not call upstream for a forbidden path: ${request.url}');
    });

    expect(
      () => service.proxyGet(callerId: 'skin', path: 'admin/delete-all'),
      throwsA(isA<DecentProxyForbiddenPathException>()),
    );
  });

  test('normalizes a leading slash in the path', () async {
    await linkAccount();
    late http.Request captured;
    final service = buildService((request) async {
      captured = request;
      return http.Response('ok', 200);
    });

    await service.proxyGet(callerId: 'skin', path: '/support/api/sn');

    expect(
      captured.url.toString(),
      'https://decentespresso.com/support/api/sn',
    );
  });

  test('forwards query parameters', () async {
    await linkAccount();
    late http.Request captured;
    final service = buildService((request) async {
      captured = request;
      return http.Response('ok', 200);
    });

    await service.proxyGet(
      callerId: 'skin',
      path: 'support/api/email',
      query: {'subject': 'hi there', 'body': 'b'},
    );

    expect(captured.url.queryParameters['subject'], 'hi there');
    expect(captured.url.queryParameters['body'], 'b');
  });

  test('emits an audit log line carrying the caller identity', () async {
    await linkAccount();
    final records = <LogRecord>[];
    final sub = Logger('DecentProxy').onRecord.listen(records.add);
    addTearDown(sub.cancel);

    final service = buildService((request) async {
      return http.Response('ok', 200);
    });

    await service.proxyGet(callerId: 'plugin:dye2', path: 'support/api/sn');

    expect(
      records.any(
        (r) =>
            r.message.contains('plugin:dye2') &&
            r.message.contains('support/api/sn'),
      ),
      isTrue,
    );
  });
}
