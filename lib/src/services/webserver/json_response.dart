import 'dart:convert';
import 'package:shelf/shelf.dart';

const _jsonHeaders = {'Content-Type': 'application/json'};

Response jsonOk(Object? data) => Response.ok(
      jsonEncode(data),
      headers: _jsonHeaders,
    );

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

