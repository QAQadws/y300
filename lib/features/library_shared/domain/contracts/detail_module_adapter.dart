import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

enum DetailRefreshStatus {
  immediate,
  queued,
  skipped,
}

class DetailRefreshResult {
  const DetailRefreshResult({
    required this.status,
    this.message,
    this.queuePosition,
    this.estimatedDuration,
  });

  final DetailRefreshStatus status;
  final String? message;
  final int? queuePosition;
  final Duration? estimatedDuration;

  bool get shouldReload => status == DetailRefreshStatus.immediate;

  static const immediate = DetailRefreshResult(
    status: DetailRefreshStatus.immediate,
  );

  static const skipped = DetailRefreshResult(
    status: DetailRefreshStatus.skipped,
  );

  factory DetailRefreshResult.queued({
    required Duration estimatedDuration,
    int? queuePosition,
    String? message,
  }) {
    return DetailRefreshResult(
      status: DetailRefreshStatus.queued,
      message: message ?? '更新预计耗时${_formatSeconds(estimatedDuration)}s',
      queuePosition: queuePosition,
      estimatedDuration: estimatedDuration,
    );
  }

  static String _formatSeconds(Duration duration) {
    final tenths = (duration.inMilliseconds / 100).round();
    if (tenths % 10 == 0) {
      return '${tenths ~/ 10}';
    }
    return (tenths / 10).toStringAsFixed(1);
  }
}

/// 统一详情页模块适配合同。
///
/// 该合同用于承接漫画/小说在详情页上的字段与行为差异。
abstract class DetailModuleAdapter {
  /// 模块标识。
  LibraryModuleKey get moduleKey;

  /// 读取详情头部信息。
  Future<LibraryDetailHeader> loadHeader({
    required String workId,
  });

  /// 读取章节列表。
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  });

  /// 章节状态动作。
  Future<void> markChapterRead({
    required String workId,
    required String episodeId,
    required bool isRead,
  });

  Future<void> markChapterBookmarked({
    required String workId,
    required String episodeId,
    required bool isBookmarked,
  });

  Future<void> markChapterDownloaded({
    required String workId,
    required String episodeId,
    required bool isDownloaded,
  });

  Future<void> clearAllReadState({
    required String workId,
  });

  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  });

  /// 下载动作。
  Future<void> downloadUnread({required String workId});

  Future<void> downloadAll({required String workId});

  /// 作品级动作。
  Future<DetailRefreshResult> refreshWork({required String workId});

  Future<void> updateIntro({
    required String workId,
    required String intro,
  });

  /// 修改作品所在分类（详情页 more 菜单动作）。
  Future<void> moveWorkToCategory({
    required String workId,
    required String toCategoryId,
  });

  /// 读取当前模块可选分类列表。
  Future<List<LibraryCategory>> loadCategories();

  /// 读取当前作品绑定标签。
  Future<List<LibraryTag>> getWorkTags({
    required String workId,
  });

  /// 读取可用标签池。
  Future<List<LibraryTag>> getAllTags();

  /// 绑定已存在标签到作品。
  Future<void> addExistingTagToWork({
    required String workId,
    required String tagId,
  });

  /// 新建标签并绑定到作品。
  Future<void> addNewTagToWork({
    required String workId,
    required String tagName,
  });

  /// 从作品上移除标签。
  Future<void> removeTagFromWork({
    required String workId,
    required String tagId,
  });

  /// 原帖路由参数。
  Future<ThreadRouteTarget?> getThreadRouteTarget({
    required String workId,
  });

  /// 阅读器路由参数（开始/继续）。
  Future<ReaderRouteTarget?> getReaderRouteTarget({
    required String workId,
    required bool preferContinue,
  });
}

/// 作品元数据编辑能力。
///
/// 这是漫画 Phase 7 的可选合同：统一详情页只在 adapter 实现该接口时显示
/// “编辑作品信息”，小说/收藏无需感知漫画的自定义标题与搜索关键词语义。
abstract class DetailMetadataEditor {
  Future<void> updateCustomMetadata({
    required String workId,
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  });
}

/// 原帖跳转目标。
class ThreadRouteTarget {
  const ThreadRouteTarget({
    required this.tid,
    this.subject,
  });

  final String tid;
  final String? subject;
}

/// 阅读器跳转目标。
class ReaderRouteTarget {
  const ReaderRouteTarget({
    required this.workId,
    required this.episodeId,
  });

  final String workId;
  final String episodeId;
}
