import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/skin_feature/skin_view.dart';

void main() {
  group('classifySkinNavigation', () {
    test('allows localhost:3000 and its sub-paths', () {
      expect(
        classifySkinNavigation(Uri.parse('http://localhost:3000/')),
        SkinNavDecision.allow,
      );
      expect(
        classifySkinNavigation(Uri.parse('http://localhost:3000/foo?x=1')),
        SkinNavDecision.allow,
      );
    });

    test('allows the settings plugin path', () {
      expect(
        classifySkinNavigation(
          Uri.parse('http://localhost:8080/api/v1/plugins/settings.reaplugin'),
        ),
        SkinNavDecision.allow,
      );
    });

    test('opens external https links in the browser', () {
      expect(
        classifySkinNavigation(
          Uri.parse('https://decentespresso.com/doc/quickstart/'),
        ),
        SkinNavDecision.openExternal,
      );
    });

    test('opens external (non-localhost) http links in the browser', () {
      expect(
        classifySkinNavigation(Uri.parse('http://example.com/page')),
        SkinNavDecision.openExternal,
      );
    });

    test('blocks non-http schemes', () {
      expect(
        classifySkinNavigation(Uri.parse('mailto:hi@example.com')),
        SkinNavDecision.block,
      );
      expect(
        classifySkinNavigation(Uri.parse('tel:+123')),
        SkinNavDecision.block,
      );
    });

    test('blocks a null url', () {
      expect(classifySkinNavigation(null), SkinNavDecision.block);
    });
  });
}
