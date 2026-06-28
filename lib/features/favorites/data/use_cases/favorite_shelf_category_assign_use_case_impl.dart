import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';

class DefaultFavoriteShelfCategoryAssignUseCase
    implements ShelfCategoryAssignUseCase {
  const DefaultFavoriteShelfCategoryAssignUseCase({
    required LocalFavoriteRepository repository,
  }) : _repository = repository;

  final LocalFavoriteRepository _repository;

  @override
  Future<ShelfCategoryAssignResult> assign({
    required Set<String> workIds,
    required String sourceCategoryId,
    required String targetCategoryId,
  }) async {
    final assignedWorkIds = <String>[];
    final failedWorkIds = <String>[];
    final normalizedTargetCategoryId = targetCategoryId.trim();

    for (final rawWorkId in workIds) {
      final workId = rawWorkId.trim();
      final tid = FavoriteShelfWorkId.parseTid(workId);
      if (tid == null) {
        failedWorkIds.add(rawWorkId);
        continue;
      }
      try {
        await _repository.moveThreadToCategory(
          tid: tid,
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
