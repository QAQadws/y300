import 'package:y300/features/comic/data/comic_repository.dart';

/// Coordinates duplicate comic merging without exposing SQLite details to UI or
/// favorite sync. A duplicate is any connected group of comics whose episodes
/// share at least one source tid.
class ComicDuplicateMergeService {
  const ComicDuplicateMergeService({
    required ComicDuplicateMergeRepository repository,
  }) : _repository = repository;

  final ComicDuplicateMergeRepository _repository;

  Future<ComicDuplicateMergeSummary> mergeAllDuplicates() async {
    var summary = const ComicDuplicateMergeSummary.empty();
    final processed = <String>{};

    while (true) {
      final groups = await _repository.findDuplicateGroups();
      ComicDuplicateGroup? nextGroup;
      for (final group in groups) {
        if (group.comicIds.any((comicId) => !processed.contains(comicId))) {
          nextGroup = group;
          break;
        }
      }
      if (nextGroup == null) {
        return summary;
      }

      final result = await _repository.mergeDuplicateGroup(
        comicIds: nextGroup.comicIds,
      );
      processed.addAll(nextGroup.comicIds);
      processed.add(result.targetComicId);
      processed.addAll(result.mergedComicIds);
      summary = summary.combine(result);
    }
  }

  /// Merges the duplicate group connected to [comicId]. This is intentionally
  /// smaller than "merge all" so ingest/refresh flows can clean up only the work
  /// they just touched.
  Future<ComicDuplicateMergeResult> mergeComic({
    required String comicId,
  }) async {
    final normalized = comicId.trim();
    if (normalized.isEmpty) {
      return const ComicDuplicateMergeResult.unchanged(targetComicId: '');
    }
    final groups = await _repository.findDuplicateGroups(comicId: normalized);
    if (groups.isEmpty) {
      return ComicDuplicateMergeResult.unchanged(targetComicId: normalized);
    }
    final group = groups.firstWhere(
      (candidate) => candidate.comicIds.contains(normalized),
      orElse: () => groups.first,
    );
    return _repository.mergeDuplicateGroup(comicIds: group.comicIds);
  }
}
