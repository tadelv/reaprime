import 'package:drift/drift.dart';
import 'package:reaprime/src/models/data/bean.dart' as domain;
import 'package:reaprime/src/services/database/database.dart';

/// Maps between domain Bean/BeanBatch models and Drift table rows.
class BeanMapper {
  /// Convert a Drift Bean row to a domain Bean.
  static domain.Bean fromRow(Bean row) {
    return domain.Bean(
      id: row.id,
      roaster: row.roaster,
      name: row.name,
      species: row.species,
      decaf: row.decaf,
      decafProcess: row.decafProcess,
      country: row.country,
      region: row.region,
      producer: row.producer,
      variety: row.variety,
      altitude: row.altitude,
      processing: row.processing,
      notes: row.notes,
      archived: row.archived,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      extras: row.extras,
    );
  }

  /// Convert a domain Bean to a Drift companion for insert/update.
  static BeansCompanion toCompanion(domain.Bean bean) {
    return BeansCompanion(
      id: Value(bean.id),
      roaster: Value(bean.roaster),
      name: Value(bean.name),
      species: Value(bean.species),
      decaf: Value(bean.decaf),
      decafProcess: Value(bean.decafProcess),
      country: Value(bean.country),
      region: Value(bean.region),
      producer: Value(bean.producer),
      variety: Value(bean.variety),
      altitude: Value(bean.altitude),
      processing: Value(bean.processing),
      notes: Value(bean.notes),
      archived: Value(bean.archived),
      createdAt: Value(bean.createdAt),
      updatedAt: Value(bean.updatedAt),
      extras: Value(bean.extras),
    );
  }

  /// Convert a Drift BeanBatch row to a domain BeanBatch.
  static domain.BeanBatch batchFromRow(BeanBatche row) {
    return domain.BeanBatch(
      id: row.id,
      beanId: row.beanId,
      roastDate: row.roastDate,
      roastLevel: row.roastLevel,
      harvestDate: row.harvestDate,
      qualityScore: row.qualityScore,
      price: row.price,
      currency: row.currency,
      weight: row.weight,
      weightRemaining: row.weightRemaining,
      buyDate: row.buyDate,
      openDate: row.openDate,
      bestBeforeDate: row.bestBeforeDate,
      freezeDate: row.freezeDate,
      unfreezeDate: row.unfreezeDate,
      frozen: row.frozen,
      archived: row.archived,
      notes: row.notes,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      extras: row.extras,
    );
  }

  /// Convert a domain BeanBatch to a Drift companion.
  static BeanBatchesCompanion batchToCompanion(domain.BeanBatch batch) {
    return BeanBatchesCompanion(
      id: Value(batch.id),
      beanId: Value(batch.beanId),
      roastDate: Value(batch.roastDate),
      roastLevel: Value(batch.roastLevel),
      harvestDate: Value(batch.harvestDate),
      qualityScore: Value(batch.qualityScore),
      price: Value(batch.price),
      currency: Value(batch.currency),
      weight: Value(batch.weight),
      weightRemaining: Value(batch.weightRemaining),
      buyDate: Value(batch.buyDate),
      openDate: Value(batch.openDate),
      bestBeforeDate: Value(batch.bestBeforeDate),
      freezeDate: Value(batch.freezeDate),
      unfreezeDate: Value(batch.unfreezeDate),
      frozen: Value(batch.frozen),
      archived: Value(batch.archived),
      notes: Value(batch.notes),
      createdAt: Value(batch.createdAt),
      updatedAt: Value(batch.updatedAt),
      extras: Value(batch.extras),
    );
  }
}
