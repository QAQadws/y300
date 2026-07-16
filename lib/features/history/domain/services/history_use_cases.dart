import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';
import 'package:y300/features/history/domain/services/history_visit_draft_normalizer.dart';

class QueryHistoryUseCase {
  const QueryHistoryUseCase({
    required HistoryRepository repository,
    required HistoryVisitDraftNormalizer normalizer,
  }) : _repository = repository,
       _normalizer = normalizer;

  final HistoryRepository _repository;
  final HistoryVisitDraftNormalizer _normalizer;

  Future<HistoryQueryPage> call(HistoryQuery query) {
    return _repository.query(
      query.copyWith(
        searchText: _normalizer.normalizeSearchText(query.searchText),
        targetTypes: Set<HistoryTargetType>.unmodifiable(query.targetTypes),
        limit: query.limit.clamp(1, 100),
      ),
    );
  }
}

class DeleteHistoryEntryUseCase {
  const DeleteHistoryEntryUseCase(this._repository);

  final HistoryRepository _repository;

  Future<void> call(HistoryTargetKey target) => _repository.delete(target);
}

class RestoreHistoryEntryUseCase {
  const RestoreHistoryEntryUseCase(this._repository);

  final HistoryRepository _repository;

  Future<void> call(HistoryEntry entry) => _repository.restore(entry);
}

class ClearHistoryUseCase {
  const ClearHistoryUseCase(this._repository);

  final HistoryRepository _repository;

  Future<void> call() => _repository.clear();
}
