import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';
import 'package:y300/features/history/domain/services/history_clock.dart';
import 'package:y300/features/history/domain/services/history_diagnostic_recorder.dart';
import 'package:y300/features/history/domain/services/history_visit_draft_normalizer.dart';
import 'package:y300/features/history/domain/services/history_visit_recorder.dart';

class RecordHistoryVisitUseCase implements HistoryVisitRecorder {
  const RecordHistoryVisitUseCase({
    required HistoryRepository repository,
    required HistoryVisitDraftNormalizer normalizer,
    required HistoryClock clock,
    HistoryDiagnosticRecorder diagnosticRecorder =
        const NoopHistoryDiagnosticRecorder(),
  }) : _repository = repository,
       _normalizer = normalizer,
       _clock = clock,
       _diagnosticRecorder = diagnosticRecorder;

  final HistoryRepository _repository;
  final HistoryVisitDraftNormalizer _normalizer;
  final HistoryClock _clock;
  final HistoryDiagnosticRecorder _diagnosticRecorder;

  Future<void> call(HistoryVisitDraft draft) => record(draft);

  @override
  Future<void> record(HistoryVisitDraft draft) async {
    final stopwatch = Stopwatch()..start();
    try {
      final normalized = _normalizer.normalize(draft);
      final now = _clock.now().toUtc();
      await _repository.recordVisit(
        HistoryEntry(
          target: normalized.target,
          title: normalized.title!,
          contextLabel: normalized.contextLabel!,
          thumbnail: normalized.thumbnail,
          sourceTid: normalized.sourceTid,
          canonicalUri: normalized.canonicalUri,
          lastPage: normalized.page,
          forumName: normalized.forumName,
          lastSurface: normalized.surface,
          firstVisitedAt: now,
          lastVisitedAt: now,
          visitCount: 1,
        ),
      );
      _diagnosticRecorder.recordWrite(
        targetType: normalized.target.type,
        surface: normalized.surface,
        outcome: HistoryDiagnosticOutcome.success,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      _diagnosticRecorder.recordWrite(
        targetType: draft.target.type,
        surface: draft.surface,
        outcome: HistoryDiagnosticOutcome.failure,
        elapsedMs: stopwatch.elapsedMilliseconds,
        errorType: error.runtimeType.toString(),
      );
      rethrow;
    }
  }
}
