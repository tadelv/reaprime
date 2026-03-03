// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shot_dao.dart';

// ignore_for_file: type=lint
mixin _$ShotDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShotRecordsTable get shotRecords => attachedDatabase.shotRecords;
  ShotDaoManager get managers => ShotDaoManager(this);
}

class ShotDaoManager {
  final _$ShotDaoMixin _db;
  ShotDaoManager(this._db);
  $$ShotRecordsTableTableManager get shotRecords =>
      $$ShotRecordsTableTableManager(_db.attachedDatabase, _db.shotRecords);
}
