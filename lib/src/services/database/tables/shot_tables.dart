import 'package:drift/drift.dart';
import 'package:reaprime/src/services/database/converters/json_converters.dart';

/// Shot records with denormalized columns for filtering + JSON blobs for complex data.
class ShotRecords extends Table {
  TextColumn get id => text()();
  DateTimeColumn get timestamp => dateTime()();

  // Denormalized columns for fast filtering/sorting
  TextColumn get profileTitle => text().nullable()();
  TextColumn get grinderId => text().nullable()();
  TextColumn get grinderModel => text().nullable()();
  TextColumn get grinderSetting => text().nullable()();
  TextColumn get beanBatchId => text().nullable()();
  TextColumn get coffeeName => text().nullable()();
  TextColumn get coffeeRoaster => text().nullable()();
  RealColumn get targetDoseWeight => real().nullable()();
  RealColumn get targetYield => real().nullable()();
  RealColumn get enjoyment => real().nullable()();
  TextColumn get espressoNotes => text().nullable()();

  // Full JSON blobs for complex nested data
  TextColumn get workflowJson =>
      text().map(const JsonMapConverter())();
  TextColumn get annotationsJson =>
      text().map(const NullableJsonMapConverter()).nullable()();

  // Measurements stored separately — can be large, loaded lazily
  TextColumn get measurementsJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}
