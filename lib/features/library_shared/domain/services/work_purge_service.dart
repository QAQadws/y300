import 'package:y300/features/thread/domain/thread_content_classifier.dart';

// 阶段 0 契约冻结（书架多选与取消收藏方案）。
//
// 作品清除服务：当一个作品再无任何活跃收藏来源时，删除它的全部本地资源。
//
// 重要边界：这与现有 `ComicRepository.removeFromShelf`（注释明确「保留章节和
// 阅读缓存」，仅移出书架，用于收藏同步取消的旧路径）是两种不同语义。
// purge 是破坏性、不可逆的全量清除，绝不可复用 removeFromShelf。
//
// 清除范围（按需求）：
//   - 书架记录 / 作品行 / 章节
//   - 阅读状态（library_work_state + library_episode_state）
//   - 自定义信息（标题/作者/封面字段）
//   - 封面 / 图片缓存（按 owner）
//   - 本地下载（按 comicId 目录）
//   - 收藏帖行（favorite_threads 标记 removed）
//
// 实现落在阶段 2，按 ThreadContentKind 分派 comic/novel 两种策略。

/// 单个作品清除的结构化结果，便于上层报告与排错。
class WorkPurgeResult {
  const WorkPurgeResult({
    required this.workId,
    required this.kind,
    required this.purgedDownload,
    required this.purgedCache,
    this.errors = const <String>[],
  });

  final String workId;
  final ThreadContentKind kind;

  /// 是否清除了本地下载产物。
  final bool purgedDownload;

  /// 是否清除了封面/图片缓存。
  final bool purgedCache;

  /// 清除过程中遇到的非致命错误（例如某项缓存删除失败）。
  final List<String> errors;

  bool get hasError => errors.isNotEmpty;
}

/// 作品清除服务（破坏性，不可逆）。
abstract class WorkPurgeService {
  /// 清除单个作品的全部本地资源。
  ///
  /// 调用方负责在调用前确认该作品确实再无活跃收藏来源；本服务只负责清除。
  Future<WorkPurgeResult> purge({
    required String workId,
    required ThreadContentKind kind,
  });
}
