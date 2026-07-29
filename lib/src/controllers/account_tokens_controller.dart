import 'package:logging/logging.dart';
import 'package:reaprime/src/services/account/proxy_token_service.dart';
import 'package:reaprime/src/services/account/proxy_token_store.dart';

/// Owns the lifecycle of user-created API-client tokens: load persisted tokens
/// into the [ProxyTokenService] at startup, mint new ones, list them for the
/// settings UI, and revoke. The [ProxyTokenService] stays a pure validator; this
/// controller is the source of truth for token metadata and persistence.
class AccountTokensController {
  final ProxyTokenService _tokenService;
  final ProxyTokenStore _store;
  final Logger _log = Logger('AccountTokensController');

  final List<PersistedProxyToken> _tokens = [];

  AccountTokensController({
    required ProxyTokenService tokenService,
    required ProxyTokenStore store,
  }) : _tokenService = tokenService,
       _store = store;

  /// API-client tokens (never the in-memory skin token).
  List<PersistedProxyToken> get tokens => List.unmodifiable(_tokens);

  /// Loads persisted tokens and registers each into the validator. Best-effort:
  /// a secure-store failure (e.g. headless Linux) leaves the proxy with only the
  /// skin token rather than failing startup.
  Future<void> initialize() async {
    try {
      final persisted = await _store.load();
      _tokens
        ..clear()
        ..addAll(persisted);
      for (final t in persisted) {
        _tokenService.registerToken(
          t.token,
          ProxyCaller(id: 'api:${t.label}', scopes: t.scopes),
        );
      }
    } catch (e, st) {
      _log.warning('Failed to load persisted proxy tokens', e, st);
    }
  }

  /// Mints a named token, registers it, persists it, and returns the raw bearer
  /// secret for one-time display. [write] grants the `account:proxy:write` scope
  /// (inert until the write proxy #355 lands).
  Future<String> create({required String label, bool write = false}) async {
    final token = ProxyTokenService.generateToken();
    final scopes = <String>{
      ProxyTokenService.scopeAccountProxy,
      if (write) ProxyTokenService.scopeAccountProxyWrite,
    };
    final record = PersistedProxyToken(
      token: token,
      label: label,
      scopes: scopes,
      createdAt: DateTime.now(),
    );

    _tokenService.registerToken(
      token,
      ProxyCaller(id: 'api:$label', scopes: scopes),
    );
    _tokens.add(record);
    await _store.save(_tokens);
    return token;
  }

  /// Revokes a token: removes it from the validator, the in-memory list, and the
  /// persisted store.
  Future<void> revoke(String token) async {
    _tokenService.revokeToken(token);
    _tokens.removeWhere((t) => t.token == token);
    await _store.save(_tokens);
  }
}
