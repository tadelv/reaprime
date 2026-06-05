part of '../webserver_service.dart';

class AccountHandler {
  final DecentAccountService _accountService;
  final Logger _log = Logger('AccountHandler');

  AccountHandler({required DecentAccountService accountService})
    : _accountService = accountService;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/account/decent', _handleStatus);
    app.post('/api/v1/account/decent/login', _handleLogin);
    app.delete('/api/v1/account/decent', _handleLogout);
  }

  Future<Response> _handleStatus(Request request) async {
    return jsonOk(await _statusJson());
  }

  Future<Response> _handleLogin(Request request) async {
    final payload = await request.readAsString();
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return jsonBadRequest({'error': 'Expected a JSON object'});
      }
      json = decoded;
    } on FormatException {
      return jsonBadRequest({'error': 'Invalid JSON'});
    }

    final email = json['email'];
    final password = json['password'];
    if (email is! String || email.trim().isEmpty) {
      return jsonBadRequest({'error': 'email is required'});
    }
    if (password is! String || password.isEmpty) {
      return jsonBadRequest({'error': 'password is required'});
    }

    try {
      final ok = await _accountService.login(email, password);
      if (!ok) {
        return jsonUnauthorized({
          'error': 'Invalid Decent account email or password',
        });
      }
      return jsonOk(await _statusJson());
    } catch (e, st) {
      _log.warning('Decent account login failed', e, st);
      return jsonError({'error': 'Failed to link Decent account'});
    }
  }

  Future<Response> _handleLogout(Request request) async {
    await _accountService.logout();
    return jsonOk(await _statusJson());
  }

  Future<Map<String, dynamic>> _statusJson() async {
    final loggedIn = await _accountService.isLoggedIn();
    return {
      'loggedIn': loggedIn,
      'email': loggedIn ? await _accountService.getEmail() : null,
    };
  }
}
