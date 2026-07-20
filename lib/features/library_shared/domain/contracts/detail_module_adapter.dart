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

  Future<void> markChapterBookmarked({
    required String workId,
    required String episodeId,
    required bool isBookmarked,
  });

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

/// Optional chapter read-state capability.
///
/// Modules such as novels that cannot reliably infer read completion do not
/// implement this contract. Shared detail UI must discover the capability
/// before exposing read filters or mutations.
abstract interface class DetailChapterReadStateAdapter {
  Future<void> markChapterRead({
    required String workId,
    required String episodeId,
    required bool isRead,
  });

  /// Reset one chapter's reading state without touching its bookmark or
  /// download state.
  Future<void> resetChapterReadingState({
    required String workId,
    required String episodeId,
  });
}

/// 章节下载可选能力。
///
/// 只有拥有独立下载产物的模块实现该合同。共享详情页通过能力发现决定是否
/// 展示下载入口与下载筛选，避免要求水合即离线的模块维护重复副本。
abstract interface class DetailChapterDownloadAdapter {
  Future<void> markChapterDownloaded({
    required String workId,
    required String episodeId,
    required bool isDownloaded,
  });

  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  });

  Future<void> downloadUnread({required String workId});

  Future<void> downloadAll({required String workId});
}

/// 作品元数据编辑能力。
///
/// 统一详情页只在 adapter 实现该接口时显示“编辑作品信息”。字段文案和
/// 搜索关键词能力由配置声明，避免共享页面按漫画/小说写条件分支。
abstract class DetailMetadataEditor {
  DetailMetadataEditorConfig get metadataEditorConfig;

  Future<void> updateCustomMetadata({
    required String workId,
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  });
}

class DetailMetadataEditorConfig {
  const DetailMetadataEditorConfig({
    this.authorLabel = '作者',
    this.translationGroupLabel = '汉化组',
    this.sourceAuthorLabel = '来源作者',
    this.sourceTranslationGroupLabel = '来源汉化组',
    this.showAuthor = true,
    this.showTranslationGroup = true,
    this.showSearchTitle = true,
    this.fallbackToDisplaySourceValues = true,
  });

  final String authorLabel;
  final String translationGroupLabel;
  final String sourceAuthorLabel;
  final String sourceTranslationGroupLabel;
  final bool showAuthor;
  final bool showTranslationGroup;
  final bool showSearchTitle;
  final bool fallbackToDisplaySourceValues;
}

/// 作品目录 URL 编辑能力。
///
/// 仅需要目录发现策略的模块实现该合同。统一详情页据此显示“配置目录”，
/// 并保持来源解析值与用户覆盖值相互独立。
abstract class DetailCatalogEditor {
  Future<DetailCatalogConfiguration> loadCatalogConfiguration({
    required String workId,
  });

  /// 保存用户目录覆盖值。传入 null 或空白表示恢复使用来源目录。
  Future<void> updateCatalogOverride({
    required String workId,
    String? catalogUrl,
  });
}

class DetailCatalogConfiguration {
  const DetailCatalogConfiguration({
    required this.sourceCatalogUrl,
    required this.customCatalogUrl,
  });

  final String? sourceCatalogUrl;
  final String? customCatalogUrl;

  String get initialInputValue {
    return _firstNonBlank(customCatalogUrl, sourceCatalogUrl) ?? '';
  }
}

/// 自定义封面编辑可选合同。
///
/// 漫画和小说可以按需实现：从本地图片设自定义封面、调整已有自定义封面的
/// 焦点。统一详情页据此决定是否展示相关入口。
///
/// 焦点为归一化 [-1,1] 坐标（对齐 Flutter `Alignment`），null 表示居中。
abstract class DetailCoverEditor {
  /// 当前 Header 是否有可取消的封面。
  ///
  /// 漫画通常只允许取消自定义封面；小说可以把来源封面也持久隐藏。
  bool canRemoveCover(LibraryDetailHeader header);

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

  /// 取消当前封面。具体是恢复来源封面还是持久隐藏来源封面，由模块决定。
  Future<void> removeCustomCover({required String workId});
}

/// 原帖跳转目标。
class ThreadRouteTarget {
  const ThreadRouteTarget({
    required this.tid,
    this.subject,
    this.initialPage,
    this.targetPid,
  });

  final String tid;
  final String? subject;
  final int? initialPage;
  final String? targetPid;
}

/// 阅读器跳转目标。
class ReaderRouteTarget {
  const ReaderRouteTarget({required this.workId, required this.episodeId});

  final String workId;
  final String episodeId;
}

String? _firstNonBlank(String? preferred, String? fallback) {
  final first = preferred?.trim();
  if (first != null && first.isNotEmpty) {
    return first;
  }
  final second = fallback?.trim();
  return second == null || second.isEmpty ? null : second;
}
