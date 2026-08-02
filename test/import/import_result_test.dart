import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/import_result.dart';

void main() {
  test(
    'converts partial backup sections into onboarding counts and errors',
    () {
      final result = ImportResult.fromBackupSections({
        'profiles': {'imported': 3, 'skipped': 1},
        'shots': {
          'imported': 2,
          'errors': ['bad shot'],
        },
      });

      expect(result.profilesImported, 3);
      expect(result.profilesSkipped, 1);
      expect(result.shotsImported, 2);
      expect(result.errors.single.filename, 'shots');
      expect(result.errors.single.reason, 'bad shot');
    },
  );
}
