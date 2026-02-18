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

Response jsonBadRequest(Object? data) => Response.badRequest(
      body: jsonEncode(data),
    );

Response jsonNotFound(Object? data) => Response.notFound(
      jsonEncode(data),
    );

Response jsonError(Object? data) => Response.internalServerError(
      body: jsonEncode(data),
    );
