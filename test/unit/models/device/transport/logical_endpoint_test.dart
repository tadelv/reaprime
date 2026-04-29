import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/transport/logical_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogicalEndpoint', () {
    test('every Endpoint value implements LogicalEndpoint with non-null wire ids', () {
      for (final ep in Endpoint.values) {
        expect(ep, isA<LogicalEndpoint>(), reason: '${ep.name} must implement LogicalEndpoint');
        expect(ep.uuid, isNotNull, reason: '${ep.name} uuid');
        expect(ep.representation, isNotNull, reason: '${ep.name} representation');
        expect(ep.name, isNotEmpty);
      }
    });
  });
}
