import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';

class DefaultComicShelfCategoryAssignUseCase
    implements ShelfCategoryAssignUseCase {
  const DefaultComicShelfCategoryAssignUseCase({
    required ComicRepository repository,
  }) : _repository = repository;

  final ComicRepository _repository;

  @override
  Future<ShelfCategoryAssignResult> assign({
    required Set<String> workIds,
    required String sourceCategoryId,
    required String targetCategoryId,
  }) async {
    final assignedWorkIds = <String>[];
    final failedWorkIds = <String>[];
    final normalizedSourceCategoryId = sourceCategoryId.trim();
    final normalizedTargetCategoryId = targetCategoryId.trim();

    for (final rawWorkId in workIds) {
      final workId = rawWorkId.trim();
      if (workId.isEmpty) {
        failedWorkIds.add(rawWorkId);
        continue;
      }
      try {
        await _repository.moveComicToCategory(
          comicId: workId,
          fromCategoryId: normalizedSourceCategoryId,
          toCategoryId: normalizedTargetCategoryId,
        );
        assignedWorkIds.add(workId);
      } catch (_) {
        failedWorkIds.add(workId);
      }
    }

    return ShelfCategoryAssignResult(
      assignedWorkIds: assignedWorkIds,
      failedWorkIds: failedWorkIds,
      targetCategoryId: normalizedTargetCategoryId,
    );
  }
}
