import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';
import 'package:y300/features/history/domain/services/history_diagnostic_recorder.dart';
import 'package:y300/features/history/domain/services/history_visit_draft_normalizer.dart';

class QueryHistoryUseCase {
  const QueryHistoryUseCase({
    required HistoryRepository repository,
    required HistoryVisitDraftNormalizer normalizer,
    HistoryDiagnosticRecorder diagnosticRecorder =
        const NoopHistoryDiagnosticRecorder(),
  }) : _repository = repository,
       _normalizer = normalizer,
       _diagnosticRecorder = diagnosticRecorder;

  final HistoryRepository _repository;
  final HistoryVisitDraftNormalizer _normalizer;
  final HistoryDiagnosticRecorder _diagnosticRecorder;

  Future<HistoryQueryPage> call(HistoryQuery query) async {
    final stopwatch = Stopwatch()..start();
    final searching = query.searchText.trim().isNotEmpty;
    try {
      final page = await _repository.query(
        query.copyWith(
          searchText: _normalizer.normalizeSearchText(query.searchText),
          targetTypes: Set<HistoryTargetType>.unmodifiable(query.targetTypes),
          limit: query.limit.clamp(1, 100),
        ),
      );
      _diagnosticRecorder.recordQuery(
        outcome: HistoryDiagnosticOutcome.success,
        elapsedMs: stopwatch.elapsedMilliseconds,
        searching: searching,
        itemCount: page.items.length,
        hasMore: page.hasMore,
      );
      return page;
    } catch (error) {
      _diagnosticRecorder.recordQuery(
        outcome: HistoryDiagnosticOutcome.failure,
        elapsedMs: stopwatch.elapsedMilliseconds,
        searching: searching,
        errorType: error.runtimeType.toString(),
      );
      rethrow;
    }
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
