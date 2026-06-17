import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart'
    show CredentialStore;

/// Thrown when a proxied call is attempted but no Decent account is linked.
/// Front doors map this to HTTP 401.
class DecentAccountNotLinkedException implements Exception {
  @override
  String toString() => 'DecentAccountNotLinkedException: no account linked';
}

/// Thrown when a caller requests a path outside the allowed proxy surface.
/// Front doors map this to HTTP 403.
class DecentProxyForbiddenPathException implements Exception {
  final String path;
  DecentProxyForbiddenPathException(this.path);
  @override
  String toString() =>
      'DecentProxyForbiddenPathException: path not allowed: $path';
}

/// An upstream response, ready to be relayed to the caller as-is.
class DecentProxyResponse {
  final int statusCode;
  final Map<String, String> headers;
  final String body;

  DecentProxyResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });
}

/// Auth-enriching reverse proxy for the Decent backend.
///
/// This is the **single owner of credential use** for network clients: it reads
/// the stored Decent credentials, attaches them as Basic auth, forwards the
/// request to `decentespresso.com`, and relays the upstream status + body back.
/// Callers never see the credentials or the `Authorization` header. Every call
/// must carry a [callerId] (skin / plugin id / api-client) so use is auditable.
///
/// Forwarding is restricted to explicit methods and the `support/api/` prefix.
/// See `doc/plans/account-proxy-design.md`.
class DecentProxyService {
  final http.Client _httpClient;
  final CredentialStore _store;
  final String baseUrl;

  /// Path prefixes the proxy is allowed to forward to (no leading slash).
  final Set<String> allowedPrefixes;

  final Logger _log = Logger('DecentProxy');

  /// Response headers never relayed to callers (auth/session/transport).
  ///
  /// `content-length`/`content-encoding` are dropped because the http client
  /// already decoded the body into [DecentProxyResponse.body]; relaying the
  /// upstream values would describe the encoded bytes and corrupt the response.
  static const _strippedResponseHeaders = {
    'set-cookie',
    'www-authenticate',
    'authorization',
    'connection',
    'transfer-encoding',
    'keep-alive',
    'proxy-authenticate',
    'content-length',
    'content-encoding',
  };

  DecentProxyService({
    required http.Client httpClient,
    required CredentialStore credentialStore,
    this.baseUrl = 'https://decentespresso.com',
    this.allowedPrefixes = const {'support/api/'},
  }) : _httpClient = httpClient,
       _store = credentialStore;

  /// Forwards a request to `<baseUrl>/<path>` with the stored Decent
  /// credentials attached as Basic auth, returning the upstream response
  /// verbatim (minus sensitive headers).
  ///
  /// Throws [DecentProxyForbiddenPathException] if [path] is outside
  /// [allowedPrefixes], or [DecentAccountNotLinkedException] if no account is
  /// linked.
  Future<DecentProxyResponse> proxy({
    required String callerId,
    required String method,
    required String path,
    Map<String, String>? query,
    String? body,
    String? contentType,
  }) async {
    final normalizedMethod = method.toUpperCase();
    if (normalizedMethod != 'GET' &&
        normalizedMethod != 'POST' &&
        normalizedMethod != 'PUT') {
      throw UnsupportedError('Unsupported proxy method: $method');
    }

    final normalizedPath = _normalizePath(path);
    if (!_isAllowed(normalizedPath)) {
      _log.warning(
        'caller=$callerId $normalizedMethod /$normalizedPath -> forbidden path',
      );
      throw DecentProxyForbiddenPathException(normalizedPath);
    }

    final email = await _store.read(key: 'email');
    final password = await _store.read(key: 'password');
    if (email == null || password == null) {
      throw DecentAccountNotLinkedException();
    }

    final uri = Uri.parse('$baseUrl/$normalizedPath').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );

    final basic = base64Encode(
      utf8.encode('${email.trim()}:${password.trim()}'),
    );
    final outbound = http.Request(normalizedMethod, uri)
      ..headers['authorization'] = 'Basic $basic';
    if (contentType != null && contentType.isNotEmpty) {
      outbound.headers['content-type'] = contentType;
    }
    if (body != null) {
      outbound.body = body;
    }

    final streamedResponse = await _httpClient.send(outbound);
    final response = await http.Response.fromStream(streamedResponse);

    _log.info(
      'caller=$callerId $normalizedMethod /$normalizedPath -> ${response.statusCode}',
    );

    return DecentProxyResponse(
      statusCode: response.statusCode,
      headers: _relayHeaders(response.headers),
      body: response.body,
    );
  }

  /// Forwards a GET to `<baseUrl>/<path>`.
  Future<DecentProxyResponse> proxyGet({
    required String callerId,
    required String path,
    Map<String, String>? query,
  }) {
    return proxy(
      callerId: callerId,
      method: 'GET',
      path: path,
      query: query,
    );
  }

  /// Forwards a POST to `<baseUrl>/<path>`.
  Future<DecentProxyResponse> proxyPost({
    required String callerId,
    required String path,
    Map<String, String>? query,
    String? body,
    String? contentType,
  }) {
    return proxy(
      callerId: callerId,
      method: 'POST',
      path: path,
      query: query,
      body: body,
      contentType: contentType,
    );
  }

  /// Forwards a PUT to `<baseUrl>/<path>`.
  Future<DecentProxyResponse> proxyPut({
    required String callerId,
    required String path,
    Map<String, String>? query,
    String? body,
    String? contentType,
  }) {
    return proxy(
      callerId: callerId,
      method: 'PUT',
      path: path,
      query: query,
      body: body,
      contentType: contentType,
    );
  }

  String _normalizePath(String path) {
    var p = path.trim();
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    return p;
  }

  bool _isAllowed(String normalizedPath) {
    return allowedPrefixes.any((prefix) => normalizedPath.startsWith(prefix));
  }

  Map<String, String> _relayHeaders(Map<String, String> upstream) {
    final out = <String, String>{};
    upstream.forEach((key, value) {
      if (!_strippedResponseHeaders.contains(key.toLowerCase())) {
        out[key] = value;
      }
    });
    return out;
  }
}
