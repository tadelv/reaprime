import 'dart:convert';
import 'dart:math';

/// An authenticated proxy caller: who they are (for audit) and what they may do.
class ProxyCaller {
  /// Stable identity used in audit logs, e.g. `skin`, `api:my-laptop`.
  final String id;
  final Set<String> scopes;

  const ProxyCaller({required this.id, required this.scopes});
}

/// Issues and validates bearer tokens for the account proxy.
///
/// Two token classes (see `doc/plans/account-proxy-design.md`):
///
/// - **Skin token** — one random token per process, generated at startup and
///   injected into every `:3000` skin response. Lifetime = process; a restart
///   mints a new one and the old dies. Not persisted.
/// - **API-client token** — user-created, named, persisted, revocable. Loaded
///   into the registry via [registerToken].
class ProxyTokenService {
  static const String scopeAccountProxy = 'account:proxy';

  /// Write scope. Enforced on `POST`/`PUT` by the write proxy (#355); minted
  /// here so token issuance is ready when the write routes land.
  static const String scopeAccountProxyWrite = 'account:proxy:write';

  final Map<String, ProxyCaller> _tokens = {};
  late final String _skinToken;

  /// [skinToken] is injectable for tests; production omits it to get a fresh
  /// cryptographically-random token.
  ProxyTokenService({String? skinToken}) {
    _skinToken = skinToken ?? generateToken();
    _tokens[_skinToken] = const ProxyCaller(
      id: 'skin',
      scopes: {scopeAccountProxy},
    );
  }

  /// The current process's skin token. Injected into served skin HTML on :3000.
  String get skinToken => _skinToken;

  /// Registers a user-managed API-client token.
  void registerToken(String token, ProxyCaller caller) {
    _tokens[token] = caller;
  }

  /// Revokes a previously-registered token. The skin token cannot be revoked
  /// this way — it lives for the process lifetime.
  void revokeToken(String token) {
    if (token == _skinToken) return;
    _tokens.remove(token);
  }

  /// Returns the caller for [token], or null if the token is unknown.
  ProxyCaller? validate(String token) => _tokens[token];

  /// Mints a fresh cryptographically-random bearer token. Used for the skin
  /// token and for user-created API-client tokens.
  static String generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }
}
