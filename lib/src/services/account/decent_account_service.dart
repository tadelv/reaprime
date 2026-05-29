import 'dart:convert';
import 'package:http/http.dart' as http;

abstract class CredentialStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class DecentAccountService {
  final http.Client _httpClient;
  final CredentialStore _store;
  final String baseUrl;
  DecentAccountService({
    required http.Client httpClient,
    required CredentialStore credentialStore,
    this.baseUrl = "https://decentespresso.com",
  }) : _httpClient = httpClient,
       _store = credentialStore;

  Future<bool> login(String email, String password) async {
    final response = await _authedGet(
      email,
      password,
      '/support/api/login_test',
    );

    if (response.statusCode == 200 && response.body != '0') {
      await _store.write(key: 'email', value: email);
      await _store.write(key: 'password', value: response.body);
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    await _store.delete(key: 'email');
    await _store.delete(key: 'password');
  }

  Future<bool> isLoggedIn() async => await _store.read(key: 'email') != null;

  /// Returns the stored email address, or null if not logged in.
  Future<String?> getEmail() async => _store.read(key: 'email');

  Future<List<String>> fetchSerialNumbers() async {
    final email = await _store.read(key: 'email');
    final password = await _store.read(key: 'password');
    if (email == null || password == null) {
      throw StateError('not logged in');
    }
    final response = await _authedGet(email, password, '/support/api/sn');
    if (response.statusCode != 200) {
      throw Exception(
        'serial fetch failed (${response.statusCode}): ${response.body}',
      );
    }
    if (response.body == '') {
      return [];
    }
    return response.body.trim().split('\n');
  }

  Future<bool> verifyMachineSerial(String serial) async {
    final list = await fetchSerialNumbers();
    return list.contains(serial);
  }

  Future<http.Response> _authedGet(
    String email,
    String password,
    String path,
  ) async {
    final basic = base64Encode(utf8.encode("$email:$password"));
    return await _httpClient.get(
      Uri.parse('$baseUrl$path'),
      headers: {
        'authorization': "Basic $basic",
      },
    );
  }
}
