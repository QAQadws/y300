import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';
import 'package:y300/features/history/domain/services/history_clock.dart';
import 'package:y300/features/history/domain/services/history_visit_draft_normalizer.dart';

class RecordHistoryVisitUseCase {
  const RecordHistoryVisitUseCase({
    required HistoryRepository repository,
    required HistoryVisitDraftNormalizer normalizer,
    required HistoryClock clock,
  }) : _repository = repository,
       _normalizer = normalizer,
       _clock = clock;

  final HistoryRepository _repository;
  final HistoryVisitDraftNormalizer _normalizer;
  final HistoryClock _clock;

  Future<void> call(HistoryVisitDraft draft) async {
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
  }
}
