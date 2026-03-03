import 'package:drift/drift.dart';
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

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Enable foreign keys
        await customStatement('PRAGMA foreign_keys = ON');
      },
      beforeOpen: (details) async {
        // Always enable foreign keys on each connection
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}
