import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

void main() {
  late Handler handler;
  late Set<String> allowedOrigins;

  setUp(() {
    allowedOrigins = {
      'http://localhost:3000',
      'http://127.0.0.1:3000',
    };

    handler = const Pipeline()
        .addMiddleware(accountProxyCorsMiddleware(() => allowedOrigins))
        .addMiddleware(
          corsHeaders(
            headers: {
              'Access-Control-Expose-Headers': 'ETag',
              'Access-Control-Allow-Headers':
                  'Accept, Authorization, Content-Type',
            },
          ),
        )
        .addHandler((_) => Response.ok('ok'));
  });

  Future<Response> request(
    String method,
    String path, {
    String? origin,
  }) async {
    final headers = <String, String>{};
    if (origin != null) {
      headers['origin'] = origin;
    }
    return await handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: headers,
      ),
    );
  }

  test(
    'proxy request from an allowed skin origin echoes that origin',
    () async {
      allowedOrigins.add('http://192.168.4.20:3000');

      final response = await request(
        'GET',
        '/api/v1/account/proxy/support/api/sn',
        origin: 'http://192.168.4.20:3000',
      );

      expect(
        response.headers['access-control-allow-origin'],
        'http://192.168.4.20:3000',
      );
      expect(response.headers['vary'], contains('Origin'));
    },
  );

  test(
    'proxy request allows a LAN skin origin learned after handler startup',
    () async {
      final before = await request(
        'GET',
        '/api/v1/account/proxy/support/api/sn',
        origin: 'http://192.168.4.20:3000',
      );

      allowedOrigins.add('http://192.168.4.20:3000');

      final after = await request(
        'GET',
        '/api/v1/account/proxy/support/api/sn',
        origin: 'http://192.168.4.20:3000',
      );

      expect(before.headers['access-control-allow-origin'], isNull);
      expect(
        after.headers['access-control-allow-origin'],
        'http://192.168.4.20:3000',
      );
    },
  );

  test(
    'proxy request from a disallowed origin does not get wildcard ACAO',
    () async {
      final response = await request(
        'GET',
        '/api/v1/account/proxy/support/api/sn',
        origin: 'https://evil.example',
      );

      expect(response.headers['access-control-allow-origin'], isNull);
      expect(response.headers.values, isNot(contains('*')));
    },
  );

  test(
    'proxy preflight from an allowed skin origin echoes that origin',
    () async {
      final response = await request(
        'OPTIONS',
        '/api/v1/account/proxy/support/api/sn',
        origin: 'http://localhost:3000',
      );

      expect(
        response.headers['access-control-allow-origin'],
        'http://localhost:3000',
      );
    },
  );

  test('non-proxy API paths keep the existing permissive CORS', () async {
    final response = await request(
      'GET',
      '/api/v1/devices',
      origin: 'https://any.example',
    );

    expect(
      response.headers['access-control-allow-origin'],
      'https://any.example',
    );
  });
}
