import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:reaprime/src/services/account/proxy_token_service.dart';

const _proxyCallerContextKey = 'decentProxyCaller';

/// The authenticated caller tagged onto a request by [proxyAuthMiddleware], or
/// null if the request did not pass through proxy auth.
ProxyCaller? proxyCallerOf(Request request) =>
    request.context[_proxyCallerContextKey] as ProxyCaller?;

/// Scoped bearer-token auth, applied **only** to requests under [pathPrefix].
///
/// Everything outside the prefix passes through untouched (the rest of the
/// bridge API keeps its LAN-trust model). Inside the prefix, a request must
/// present `Authorization: Bearer <token>` for a known token holding
/// [requiredScope]; otherwise it is rejected with 401 (missing/unknown) or 403
/// (known but unscoped). On success the request is tagged with its [ProxyCaller]
/// (read via [proxyCallerOf]) for audit. CORS preflight (`OPTIONS`) is allowed
/// through unauthenticated.
Middleware proxyAuthMiddleware(
  ProxyTokenService tokens, {
  String pathPrefix = '/api/v1/account/proxy/',
  String requiredScope = ProxyTokenService.scopeAccountProxy,
}) {
  return (Handler inner) {
    return (Request request) {
      if (!request.requestedUri.path.startsWith(pathPrefix)) {
        return inner(request);
      }
      // Let CORS preflight through — it carries no Authorization by design.
      if (request.method == 'OPTIONS') {
        return inner(request);
      }

      final token = _bearerToken(request.headers['authorization']);
      if (token == null) {
        return _json(401, 'Missing or malformed bearer token');
      }
      final caller = tokens.validate(token);
      if (caller == null) {
        return _json(401, 'Invalid token');
      }
      if (!caller.scopes.contains(requiredScope)) {
        return _json(403, 'Token is not scoped for $requiredScope');
      }

      return inner(
        request.change(context: {_proxyCallerContextKey: caller}),
      );
    };
  };
}

String? _bearerToken(String? authorization) {
  if (authorization == null) return null;
  const prefix = 'Bearer ';
  if (!authorization.startsWith(prefix)) return null;
  final token = authorization.substring(prefix.length).trim();
  return token.isEmpty ? null : token;
}

Response _json(int status, String error) => Response(
  status,
  body: jsonEncode({'error': error}),
  headers: {'content-type': 'application/json'},
);
