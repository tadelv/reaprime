part of '../webserver_service.dart';

/// HTTP front door for the Decent account proxy.
///
/// Forwards `GET /api/v1/account/proxy/<decent-path>` through
/// [DecentProxyService], which attaches the stored credentials and relays the
/// upstream response. Caller identity comes from [proxyAuthMiddleware] (via
/// [proxyCallerOf]); this handler assumes the middleware has already rejected
/// unauthenticated requests under this prefix.
class AccountProxyHandler {
  final DecentProxyService _proxy;

  AccountProxyHandler({required DecentProxyService proxy}) : _proxy = proxy;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/account/proxy/<rest|.*>', _handleGet);
  }

  Future<Response> _handleGet(Request request) async {
    final rest = request.params['rest'] ?? '';
    final callerId = proxyCallerOf(request)?.id ?? 'unknown';

    try {
      final result = await _proxy.proxyGet(
        callerId: callerId,
        path: rest,
        query: request.requestedUri.queryParameters,
      );
      return Response(
        result.statusCode,
        body: result.body,
        headers: result.headers,
      );
    } on DecentAccountNotLinkedException {
      return jsonUnauthorized({'error': 'Decent account not linked'});
    } on DecentProxyForbiddenPathException {
      return jsonForbidden({'error': 'Path not allowed'});
    }
  }
}
