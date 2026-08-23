import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/services/favorite_link_service.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

/// 默认 [FavoriteLinkService]：基于 `favorite_threads` 表查询，不改 schema。
///
/// 把「收藏帖 tid ⇄ 作品 workId」的隐式关联（合并机制会把多个收藏帖
/// 重指向同一 workId）封装成领域查询，取消收藏链路只依赖这个抽象，
/// 不直接拼 SQL。删除以 tid 为键，favid 仅作辅助元数据透传。
class DefaultFavoriteLinkService implements FavoriteLinkService {
  const DefaultFavoriteLinkService({
    required LocalFavoriteRepository repository,
  }) : _repository = repository;

  final LocalFavoriteRepository _repository;

  @override
  Future<FavoriteWorkLinks> linksForWork(String workId) async {
    final normalized = workId.trim();
    if (normalized.isEmpty) {
      return FavoriteWorkLinks.empty;
    }
    final records = await _repository.getActiveThreadsByWorkId(normalized);
    if (records.isEmpty) {
      return FavoriteWorkLinks(
        workId: normalized,
        kind: ThreadContentKind.unknown,
        threads: const <FavoriteThreadRef>[],
      );
    }
    return FavoriteWorkLinks(
      workId: normalized,
      // 同一 workId 的收藏帖 contentKind 理论上一致，取首条即可。
      kind: records.first.contentKind,
      threads: records
          .map(
            (record) => FavoriteThreadRef(
              tid: record.tid,
              categoryId: record.customCategoryId,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<String?> workIdForThread(String tid) async {
    final normalized = tid.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final record = await _repository.getActiveThreadByTid(normalized);
    final workId = record?.workId?.trim();
    return (workId == null || workId.isEmpty) ? null : workId;
  }

  @override
  Future<bool> hasAnyActiveThread(String workId) {
    final normalized = workId.trim();
    if (normalized.isEmpty) {
      return Future<bool>.value(false);
    }
    return _repository.hasActiveThreadForWorkId(normalized);
  }
}
