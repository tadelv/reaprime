// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workflow_dao.dart';

// ignore_for_file: type=lint
mixin _$WorkflowDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkflowsTable get workflows => attachedDatabase.workflows;
  WorkflowDaoManager get managers => WorkflowDaoManager(this);
}

class WorkflowDaoManager {
  final _$WorkflowDaoMixin _db;
  WorkflowDaoManager(this._db);
  $$WorkflowsTableTableManager get workflows =>
      $$WorkflowsTableTableManager(_db.attachedDatabase, _db.workflows);
}
