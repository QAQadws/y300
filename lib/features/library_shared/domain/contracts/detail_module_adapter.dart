import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

enum DetailRefreshStatus { immediate, queued, skipped }

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
  Future<LibraryDetailHeader> loadHeader({required String workId});

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

  Future<void> clearAllReadState({required String workId});

  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  });

  /// 下载动作。
  Future<void> downloadUnread({required String workId});

  Future<void> downloadAll({required String workId});

  /// 作品级动作。
  Future<DetailRefreshResult> refreshWork({required String workId});

  Future<void> updateIntro({required String workId, required String intro});

  /// 修改作品所在分类（详情页 more 菜单动作）。
  Future<void> moveWorkToCategory({
    required String workId,
    required String toCategoryId,
  });

  /// 读取当前模块可选分类列表。
  Future<List<LibraryCategory>> loadCategories();

  /// 原帖路由参数。
  Future<ThreadRouteTarget?> getThreadRouteTarget({required String workId});

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

/// 自定义封面编辑可选合同。
///
/// 仅漫画详情页需要：从本地图片设自定义封面、调整已有自定义封面的焦点。
/// 小说/收藏不实现该接口，统一详情页据此决定是否展示相关入口。
///
/// 焦点为归一化 [-1,1] 坐标（对齐 Flutter `Alignment`），null 表示居中。
abstract class DetailCoverEditor {
  /// 用本地图片文件设为自定义封面，并保存焦点。
  ///
  /// [sourceLocalPath] 为用户选择的原始图片；实现负责复制到受保护缓存区。
  Future<void> setCustomCoverFromLocalFile({
    required String workId,
    required String sourceLocalPath,
    double? focusX,
    double? focusY,
  });

  /// 仅更新已有自定义封面的焦点（不改封面文件）。
  Future<void> updateCustomCoverFocus({
    required String workId,
    required double? focusX,
    required double? focusY,
  });
}

/// 原帖跳转目标。
class ThreadRouteTarget {
  const ThreadRouteTarget({required this.tid, this.subject});

  final String tid;
  final String? subject;
}

/// 阅读器跳转目标。
class ReaderRouteTarget {
  const ReaderRouteTarget({required this.workId, required this.episodeId});

  final String workId;
  final String episodeId;
}
