import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:reaprime/src/services/account/decent_account_service.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:shelf_plus/shelf_plus.dart';

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
  late Handler handler;
  late int loginStatus;
  late String loginBody;

  setUp(() {
    store = FakeCredentialStore();
    loginStatus = 200;
    loginBody = 'cryptpw_abc123';
    final service = DecentAccountService(
      httpClient: http_testing.MockClient((request) async {
        return http.Response(loginBody, loginStatus);
      }),
      credentialStore: store,
    );
    final app = Router().plus;
    AccountHandler(accountService: service).addRoutes(app);
    handler = app.call;
  });

  Future<Response> sendGet(String path) async {
    return handler(Request('GET', Uri.parse('http://localhost$path')));
  }

  Future<Response> sendPost(String path, Map<String, dynamic> body) async {
    return handler(
      Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  Future<Response> sendDelete(String path) async {
    return handler(Request('DELETE', Uri.parse('http://localhost$path')));
  }

  test('status reports an unlinked Decent account by default', () async {
    final response = await sendGet('/api/v1/account/decent');
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body['loggedIn'], false);
    expect(body['email'], isNull);
  });

  test('login links the account and returns linked status', () async {
    final response = await sendPost('/api/v1/account/decent/login', {
      'email': 'user@example.com',
      'password': 'secret',
    });
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body['loggedIn'], true);
    expect(body['email'], 'user@example.com');
  });

  test('login failure returns 401 and does not store credentials', () async {
    loginBody = '0';
    final response = await sendPost('/api/v1/account/decent/login', {
      'email': 'user@example.com',
      'password': 'wrong',
    });
    expect(response.statusCode, 401);
    final body = jsonDecode(await response.readAsString());
    expect(body['error'], contains('Invalid Decent account'));

    final status = await sendGet('/api/v1/account/decent');
    final statusBody = jsonDecode(await status.readAsString());
    expect(statusBody['loggedIn'], false);
  });

  test('logout removes the linked account', () async {
    await sendPost('/api/v1/account/decent/login', {
      'email': 'user@example.com',
      'password': 'secret',
    });
    final response = await sendDelete('/api/v1/account/decent');
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body['loggedIn'], false);
    expect(body['email'], isNull);
  });
}
