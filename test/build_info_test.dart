import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/build_info.dart';

void main() {
  test('appStore defaults to false', () {
    expect(BuildInfo.appStore, isFalse);
  });
}
