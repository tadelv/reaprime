import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/skin_feature/skin_view.dart';

void main() {
  group('shouldRecreateWebViewOnBlank', () {
    test('a skin that rendered is never recreated', () {
      expect(
        shouldRecreateWebViewOnBlank(rendered: true, priorRecoveries: 0),
        isFalse,
      );
      expect(
        shouldRecreateWebViewOnBlank(rendered: true, priorRecoveries: 99),
        isFalse,
      );
    });

    test('a blank skin recovers while under the cap', () {
      expect(
        shouldRecreateWebViewOnBlank(rendered: false, priorRecoveries: 0),
        isTrue,
      );
      expect(
        shouldRecreateWebViewOnBlank(
          rendered: false,
          priorRecoveries: 2,
          maxRecoveries: 3,
        ),
        isTrue,
      );
    });

    test('a blank skin stops recovering at the cap (no reload loop)', () {
      expect(
        shouldRecreateWebViewOnBlank(
          rendered: false,
          priorRecoveries: 3,
          maxRecoveries: 3,
        ),
        isFalse,
      );
      expect(
        shouldRecreateWebViewOnBlank(
          rendered: false,
          priorRecoveries: 4,
          maxRecoveries: 3,
        ),
        isFalse,
      );
    });
  });

  group('skinRenderedProbeJs', () {
    test('checks both a rendered body and the skin app bridge', () {
      expect(skinRenderedProbeJs, contains('childElementCount'));
      expect(skinRenderedProbeJs, contains('window.app'));
    });
  });
}
