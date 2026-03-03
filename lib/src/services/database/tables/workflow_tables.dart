import 'package:drift/drift.dart';
import 'package:reaprime/src/services/database/converters/json_converters.dart';

/// Stores the current workflow as a JSON blob.
/// Only one row expected — keyed by a fixed ID.
class Workflows extends Table {
  TextColumn get id => text()();
  TextColumn get workflowJson =>
      text().map(const JsonMapConverter())();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
