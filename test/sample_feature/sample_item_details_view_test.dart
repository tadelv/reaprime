import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/sample_feature/sample_item_details_view.dart';

void main() {
  group('debugViewTitle', () {
    test('returns DE1 label for a non-Bengle De1Interface', () {
      expect(debugViewTitle(MockDe1()), equals('DE1 Details'));
    });

    test('returns Bengle label for a BengleInterface', () {
      expect(debugViewTitle(MockBengle()), equals('Bengle Details'));
    });
  });
}
