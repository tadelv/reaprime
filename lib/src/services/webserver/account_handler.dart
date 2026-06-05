part of '../webserver_service.dart';

/// Read-only account status for network clients.
///
/// Credential operations (link/unlink a Decent account) are intentionally NOT
/// exposed over the network — they happen only through the app's native UI,
/// which calls [DecentAccountService] in-process. The bridge webserver has no
/// caller authentication and serves `Access-Control-Allow-Origin: *`, so a
/// network-exposed login/logout would let any LAN client or browser origin
/// store attacker credentials, unlink the account, or read the linked email.
///
/// Clients that need to *use* the account (call Decent backend endpoints) will
/// go through the auth-enriching proxy (`/api/v1/account/proxy/...`, see
/// `doc/plans/account-proxy-design.md`), which never exposes raw credentials.
class AccountHandler {
  final DecentAccountService _accountService;

  AccountHandler({required DecentAccountService accountService})
    : _accountService = accountService;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/account/decent', _handleStatus);
  }

  /// Reports whether a Decent account is linked. Deliberately does not return
  /// the linked email — that is PII and the endpoint is unauthenticated.
  Future<Response> _handleStatus(Request request) async {
    return jsonOk({'loggedIn': await _accountService.isLoggedIn()});
  }
}
