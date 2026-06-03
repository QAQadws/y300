import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/novel/data/novel_repository.dart';

class DefaultNovelShelfCategoryAssignUseCase
    implements ShelfCategoryAssignUseCase {
  const DefaultNovelShelfCategoryAssignUseCase({
    required NovelRepository repository,
  }) : _repository = repository;

  final NovelRepository _repository;

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
        await _repository.moveNovelToCategory(
          novelId: workId,
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
