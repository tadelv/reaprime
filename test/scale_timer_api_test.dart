import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/mock_scale/mock_scale.dart';

void main() {
  group('Scale timer API', () {
    test('MockScale timer methods are callable without error', () async {
      final scale = MockScale();
      await scale.startTimer();
      await scale.stopTimer();
      await scale.resetTimer();
    });
  });
}
