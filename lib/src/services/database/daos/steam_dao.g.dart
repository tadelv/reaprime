// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'steam_dao.dart';

// ignore_for_file: type=lint
mixin _$SteamDaoMixin on DatabaseAccessor<AppDatabase> {
  $SteamRecordsTable get steamRecords => attachedDatabase.steamRecords;
  SteamDaoManager get managers => SteamDaoManager(this);
}

class SteamDaoManager {
  final _$SteamDaoMixin _db;
  SteamDaoManager(this._db);
  $$SteamRecordsTableTableManager get steamRecords =>
      $$SteamRecordsTableTableManager(_db.attachedDatabase, _db.steamRecords);
}
