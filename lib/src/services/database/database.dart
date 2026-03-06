import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:reaprime/src/services/database/converters/json_converters.dart';
import 'package:reaprime/src/services/database/daos/bean_dao.dart';
import 'package:reaprime/src/services/database/daos/grinder_dao.dart';
import 'package:reaprime/src/services/database/daos/profile_dao.dart';
import 'package:reaprime/src/services/database/daos/shot_dao.dart';
import 'package:reaprime/src/services/database/daos/workflow_dao.dart';
import 'package:reaprime/src/services/database/tables/bean_tables.dart';
import 'package:reaprime/src/services/database/tables/grinder_tables.dart';
import 'package:reaprime/src/services/database/tables/profile_tables.dart';
import 'package:reaprime/src/services/database/tables/shot_tables.dart';
import 'package:reaprime/src/services/database/tables/workflow_tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Beans,
    BeanBatches,
    Grinders,
    ShotRecords,
    Workflows,
    ProfileRecords,
  ],
  daos: [
    BeanDao,
    GrinderDao,
    ShotDao,
    WorkflowDao,
    ProfileDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Create with the platform-default SQLite location.
  factory AppDatabase.defaults() {
    return AppDatabase(driftDatabase(name: 'streamline_bridge'));
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await customStatement('PRAGMA foreign_keys = ON');
        await _createIndices();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await _createIndices();
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _createIndices() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_shot_records_timestamp '
      'ON shot_records (timestamp DESC)',
    );
  }
}
