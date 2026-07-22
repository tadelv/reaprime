import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/services/webserver/debug_handler.dart';
import 'package:shelf_plus/shelf_plus.dart';

void main() {
  late ScaleController scaleController;
  late Handler handler;

  setUp(() {
    scaleController = ScaleController();
    final app = Router().plus;
    DebugHandler(scaleController: scaleController).addRoutes(app);
    handler = app.call;
  });

  tearDown(() => scaleController.dispose());

  Future<Response> get() async => await handler(
    Request(
      'GET',
      Uri.parse('http://localhost/api/v1/debug/flow-smoothing'),
    ),
  );

  Future<Response> post(Object body) async => await handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v1/debug/flow-smoothing'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  test('gets and updates flow smoothing', () async {
    final initial = await get();
    expect(initial.statusCode, 200);
    expect(jsonDecode(await initial.readAsString()), {
      'windowMs': 600,
      'movingAverageSamples': 10,
    });

    final updated = await post({
      'windowMs': 800,
      'movingAverageSamples': 6,
    });
    expect(updated.statusCode, 200);
    expect(jsonDecode(await updated.readAsString()), {
      'windowMs': 800,
      'movingAverageSamples': 6,
    });
  });

  test('rejects invalid updates atomically', () async {
    for (final body in [
      {'windowMs': '800', 'movingAverageSamples': 6},
      {'windowMs': 99, 'movingAverageSamples': 6},
      {'windowMs': 800, 'movingAverageSamples': 51},
    ]) {
      final response = await post(body);
      expect(response.statusCode, 400);
    }

    final current = await get();
    expect(jsonDecode(await current.readAsString()), {
      'windowMs': 600,
      'movingAverageSamples': 10,
    });
  });
}
