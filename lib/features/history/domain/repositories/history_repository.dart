import 'package:y300/features/history/domain/models/history_models.dart';

abstract interface class HistoryRepository {
  Future<void> recordVisit(HistoryEntry candidate);

  Future<HistoryQueryPage> query(HistoryQuery query);

  Future<void> delete(HistoryTargetKey target);

  Future<void> clear();

  Future<void> restore(HistoryEntry entry);

  Stream<HistoryChange> watchChanges();
}
