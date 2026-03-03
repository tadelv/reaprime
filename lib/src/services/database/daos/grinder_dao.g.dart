// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'grinder_dao.dart';

// ignore_for_file: type=lint
mixin _$GrinderDaoMixin on DatabaseAccessor<AppDatabase> {
  $GrindersTable get grinders => attachedDatabase.grinders;
  GrinderDaoManager get managers => GrinderDaoManager(this);
}

class GrinderDaoManager {
  final _$GrinderDaoMixin _db;
  GrinderDaoManager(this._db);
  $$GrindersTableTableManager get grinders =>
      $$GrindersTableTableManager(_db.attachedDatabase, _db.grinders);
}
