import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

const _jsonHeaders = {'Content-Type': 'application/json'};

Response jsonOk(Object? data) => Response.ok(
      jsonEncode(data),
      headers: _jsonHeaders,
    );

/// Like [jsonOk], but adds a strong `ETag` derived from the encoded body and
/// honours `If-None-Match` from the request — returns `304 Not Modified` with
/// the same `ETag` and empty body when the client's tag matches.
///
/// ETag format: `"<first 16 hex chars of sha256(body)>"` (RFC 7232 strong tag).
/// `If-None-Match: *` matches any current representation per RFC 7232 §3.2.
Response jsonOkConditional(Request request, Object? data) {
  final body = jsonEncode(data);
  final digest = sha256.convert(utf8.encode(body)).toString().substring(0, 16);
  final etag = '"$digest"';

  final ifNoneMatch = request.headers['if-none-match']?.trim();
  if (ifNoneMatch != null &&
      (ifNoneMatch == '*' || ifNoneMatch == etag)) {
    return Response.notModified(headers: {'ETag': etag});
  }

  return Response.ok(
    body,
    headers: {..._jsonHeaders, 'ETag': etag},
  );
}

Response jsonCreated(Object? data) => Response(
      201,
      body: jsonEncode(data),
      headers: _jsonHeaders,
    );

Response jsonAccepted([Object? data]) => Response(
      202,
      body: data != null ? jsonEncode(data) : null,
      headers: _jsonHeaders,
    );

Response jsonMultiStatus(Object? data) => Response(
      207,
      body: jsonEncode(data),
      headers: _jsonHeaders,
    );

Response jsonBadRequest(Object? data) => Response.badRequest(
      body: jsonEncode(data),
      headers: _jsonHeaders,
    );

Response jsonForbidden(Object? data) => Response(
      403,
      body: jsonEncode(data),
      headers: _jsonHeaders,
    );

Response jsonNotFound(Object? data) => Response.notFound(
      jsonEncode(data),
      headers: _jsonHeaders,
    );

Response jsonConflict(Object? data) => Response(
      409,
      body: jsonEncode(data),
      headers: _jsonHeaders,
    );

Response jsonError(Object? data) => Response.internalServerError(
      body: jsonEncode(data),
      headers: _jsonHeaders,
    );

Response jsonNotImplemented(Object? data) => Response(
      501,
      body: jsonEncode(data),
      headers: _jsonHeaders,
    );

Response jsonBadGateway(Object? data) => Response(
      502,
      body: jsonEncode(data),
      headers: _jsonHeaders,
    );

Response jsonServiceUnavailable(Object? data) => Response(
      503,
      body: jsonEncode(data),
      headers: _jsonHeaders,
    );

