import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'OpenAPI connect results explicitly allow a null connection error',
    () async {
      final spec = await File('assets/api/rest_v1.yml').readAsString();

      expect(
        spec,
        contains('''        connectionError:
          type: object
          nullable: true
          allOf:
            - \$ref: '#/components/schemas/ConnectionError'
'''),
      );
    },
  );

  test(
    'AsyncAPI connect results allow a JSON Schema null connection error',
    () async {
      final spec = await File('assets/api/websocket_v1.yml').readAsString();

      expect(
        spec,
        contains('''        connectionError:
          oneOf:
            - \$ref: '#/components/schemas/ConnectionError'
            - type: "null"'''),
      );
    },
  );
}
