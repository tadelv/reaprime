// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_dao.dart';

// ignore_for_file: type=lint
mixin _$ProfileDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProfileRecordsTable get profileRecords => attachedDatabase.profileRecords;
  ProfileDaoManager get managers => ProfileDaoManager(this);
}

class ProfileDaoManager {
  final _$ProfileDaoMixin _db;
  ProfileDaoManager(this._db);
  $$ProfileRecordsTableTableManager get profileRecords =>
      $$ProfileRecordsTableTableManager(
        _db.attachedDatabase,
        _db.profileRecords,
      );
}
