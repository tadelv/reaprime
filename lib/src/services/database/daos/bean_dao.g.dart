// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bean_dao.dart';

// ignore_for_file: type=lint
mixin _$BeanDaoMixin on DatabaseAccessor<AppDatabase> {
  $BeansTable get beans => attachedDatabase.beans;
  $BeanBatchesTable get beanBatches => attachedDatabase.beanBatches;
  BeanDaoManager get managers => BeanDaoManager(this);
}

class BeanDaoManager {
  final _$BeanDaoMixin _db;
  BeanDaoManager(this._db);
  $$BeansTableTableManager get beans =>
      $$BeansTableTableManager(_db.attachedDatabase, _db.beans);
  $$BeanBatchesTableTableManager get beanBatches =>
      $$BeanBatchesTableTableManager(_db.attachedDatabase, _db.beanBatches);
}
