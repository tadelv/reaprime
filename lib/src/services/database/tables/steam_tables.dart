import 'package:drift/drift.dart';
import 'package:reaprime/src/services/database/converters/json_converters.dart';

/// Steam records — analogue of ShotRecords. Single table with the
/// workflow + annotations + measurements stored as JSON blobs. Steam
/// records do not currently need denormalized columns for filtering;
/// add them when the use-case appears.
class SteamRecords extends Table {
  TextColumn get id => text()();
  DateTimeColumn get timestamp => dateTime()();

  TextColumn get workflowJson => text().map(const JsonMapConverter())();
  TextColumn get annotationsJson =>
      text().map(const NullableJsonMapConverter()).nullable()();

  TextColumn get measurementsJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}
