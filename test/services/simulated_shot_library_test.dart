import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/simulated_shot_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SimulatedShotLibrary', () {
    test('loads the three bundled shots', () async {
      final library = SimulatedShotLibrary();
      await library.ensureLoaded();

      expect(library.isLoaded, isTrue);
      expect(library.isEmpty, isFalse);
      expect(library.length, 3);
    });

    test('pickRandom returns a shot with measurements', () async {
      final library = SimulatedShotLibrary();
      await library.ensureLoaded();

      final shot = library.pickRandom(Random(1));
      expect(shot, isNotNull);
      expect(shot!.measurements, isNotEmpty);
    });

    test('ensureLoaded is idempotent', () async {
      final library = SimulatedShotLibrary();
      await library.ensureLoaded();
      await library.ensureLoaded();
      expect(library.length, 3);
    });

    test('a missing manifest yields an empty library, not a throw', () async {
      final library = SimulatedShotLibrary(
        manifestPath: 'assets/simulations/does-not-exist.json',
      );
      await library.ensureLoaded();

      expect(library.isLoaded, isTrue);
      expect(library.isEmpty, isTrue);
      expect(library.pickRandom(Random(1)), isNull);
    });
  });
}
