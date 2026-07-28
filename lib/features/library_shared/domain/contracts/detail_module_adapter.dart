import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

enum DetailRefreshStatus { immediate, queued, skipped }

enum DetailRefreshOutcomeCode {
  updated,
  chaptersChanged,
  alreadyCurrent,
  noUpdates,
  queued,
  unavailable,
}

class DetailRefreshResult {
  const DetailRefreshResult({
    required this.status,
    required this.outcomeCode,
    this.insertedCount = 0,
    this.updatedCount = 0,
    this.queuePosition,
    this.estimatedDuration,
  });

  final DetailRefreshStatus status;
  final DetailRefreshOutcomeCode outcomeCode;
  final int insertedCount;
  final int updatedCount;
  final int? queuePosition;
  final Duration? estimatedDuration;

  bool get shouldReload => status == DetailRefreshStatus.immediate;

  static const immediate = DetailRefreshResult(
    status: DetailRefreshStatus.immediate,
    outcomeCode: DetailRefreshOutcomeCode.updated,
  );

  static const skipped = DetailRefreshResult(
    status: DetailRefreshStatus.skipped,
    outcomeCode: DetailRefreshOutcomeCode.unavailable,
  );

  factory DetailRefreshResult.chaptersChanged({
    required int insertedCount,
    required int updatedCount,
  }) {
    return DetailRefreshResult(
      status: DetailRefreshStatus.immediate,
      outcomeCode: insertedCount == 0 && updatedCount == 0
          ? DetailRefreshOutcomeCode.alreadyCurrent
          : DetailRefreshOutcomeCode.chaptersChanged,
      insertedCount: insertedCount,
      updatedCount: updatedCount,
    );
  }

  factory DetailRefreshResult.queued({
    required Duration estimatedDuration,
    int? queuePosition,
  }) {
    return DetailRefreshResult(
      status: DetailRefreshStatus.queued,
      outcomeCode: DetailRefreshOutcomeCode.queued,
      queuePosition: queuePosition,
      estimatedDuration: estimatedDuration,
    );
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

/// Optional work-level reset capability. It is intentionally separate from
/// chapter read-state mutation because resetting a work also owns progress and
/// last-read pointers.
abstract interface class DetailWorkReadingResetAdapter {
  Future<void> resetWorkReadingState({required String workId});
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

/// Optional queue-backed activity state for chapter download controls.
///
/// Enqueuing is intentionally short-lived, while the button busy state must
/// remain active until the background task succeeds, fails, or is canceled.
abstract interface class DetailChapterDownloadActivityAdapter {
  Listenable? get chapterDownloadActivityListenable;

  bool isChapterDownloadActive({
    required String workId,
    required String episodeId,
  });
}

/// 章节管理面板中的一条章节。
///
/// 与 [LibraryChapterItem] 分开：列表项服务于阅读入口（已读/下载/书签），
/// 这里服务于“章节从哪来、要不要显示、能不能删”，两组字段的生命周期不同。
class DetailManagedChapter {
  const DetailManagedChapter({
    required this.episodeId,
    required this.title,
    required this.sourceTid,
    required this.isManual,
    required this.isHidden,
    this.sourceTitle,
    this.customTitle,
  });

  final String episodeId;

  /// 展示用章节名：自定义名优先，其次来源名。
  final String title;

  /// 来源章节名。清空自定义名后会回退到它，面板据此提示用户。
  final String? sourceTitle;

  /// 用户重命名的章节名；为空表示未自定义。
  final String? customTitle;

  /// 帖子 tid，同时是阅读器接口请求与原帖跳转的唯一入参。
  final String sourceTid;

  /// 用户手动添加的章节；只有它可以被移除。
  final bool isManual;

  /// 隐藏章节不出现在详情列表与阅读器章节导航中。
  final bool isHidden;
}

enum DetailChapterRemovalWarningCode {
  downloadTaskCleanupFailed,
  downloadFileCleanupFailed,
}

class DetailChapterRemovalResult {
  const DetailChapterRemovalResult({
    required this.removed,
    this.warnings = const <DetailChapterRemovalWarningCode>{},
  });

  final bool removed;
  final Set<DetailChapterRemovalWarningCode> warnings;
}

enum DetailManualChapterInputErrorCode {
  emptyInput,
  invalidUrl,
  unsupportedScheme,
  unexpectedHost,
  unsupportedThreadUrl,
  missingTid,
}

enum DetailManualChapterAddOutcomeCode { added, duplicate, invalidInput }

class DetailManualChapterAddOutcome {
  const DetailManualChapterAddOutcome({
    required this.code,
    this.inputErrorCode,
    this.expectedHost,
  });

  final DetailManualChapterAddOutcomeCode code;
  final DetailManualChapterInputErrorCode? inputErrorCode;
  final String? expectedHost;
}

/// 章节管理可选能力。
///
/// 只有能区分“解析章节”与“手动添加章节”的模块实现该合同。统一详情页据此
/// 在章节长按菜单里展示“管理章节”，共享页面不需要知道 tid 拼接规则。
abstract interface class DetailChapterManagementAdapter {
  /// 读取全部章节，包含隐藏项，按当前排序返回。
  Future<List<DetailManagedChapter>> loadManagedChapters({
    required String workId,
  });

  /// 按用户输入的帖子链接或 tid 添加手动章节。
  ///
  /// Expected validation failures are returned as stable codes. Unexpected
  /// repository or I/O failures still throw.
  Future<DetailManualChapterAddOutcome> addManualChapter({
    required String workId,
    required String input,
  });

  /// 移除手动章节。解析章节不可移除，返回 removed=false。
  ///
  /// 数据库记录删除成功后，外部下载文件清理失败不会伪装成整个操作失败，
  /// 通过 [DetailChapterRemovalResult.warnings] 向 UI 暴露清理告警。
  Future<DetailChapterRemovalResult> removeManualChapter({
    required String workId,
    required String episodeId,
  });

  Future<void> setChapterHidden({
    required String workId,
    required String episodeId,
    required bool isHidden,
  });

  /// 一次性显示/隐藏全部章节。
  Future<void> setAllChaptersHidden({
    required String workId,
    required bool isHidden,
  });

  /// 重命名章节。传入 null 或空白清除自定义名，章节名回退到来源名。
  ///
  /// 与“编辑作品信息”同一套语义：来源值只读，用户值可清空，清空即回退。
  /// 手动章节的来源名是添加时的默认名，因此同样能被重命名和还原。
  Future<void> renameChapter({
    required String workId,
    required String episodeId,
    required String? customTitle,
  });
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
    this.fields = const <LibraryMetadataField>{
      LibraryMetadataField.title,
      LibraryMetadataField.author,
      LibraryMetadataField.translationGroup,
      LibraryMetadataField.searchTitle,
    },
    this.fallbackToDisplaySourceValues = true,
  });

  final Set<LibraryMetadataField> fields;
  final bool fallbackToDisplaySourceValues;
}

enum LibraryMetadataField { title, author, translationGroup, searchTitle }

/// 作品目录 URL 编辑能力。
///
/// 仅需要目录发现策略的模块实现该合同。统一详情页据此显示“配置目录”，
/// 并保持来源解析值与用户覆盖值相互独立。
abstract class DetailCatalogEditor {
  Future<DetailCatalogConfiguration> loadCatalogConfiguration({
    required String workId,
  });

  /// 保存用户目录覆盖值。传入 null 或空白表示恢复使用来源目录。
  Future<DetailCatalogUpdateOutcome> updateCatalogOverride({
    required String workId,
    String? catalogUrl,
  });
}

enum DetailCatalogInputErrorCode {
  invalidUrl,
  incompleteUrl,
  unsupportedScheme,
  unexpectedHost,
  notTagCatalog,
}

enum DetailCatalogUpdateOutcomeCode { saved, invalidInput }

class DetailCatalogUpdateOutcome {
  const DetailCatalogUpdateOutcome({
    required this.code,
    this.inputErrorCode,
    this.expectedHost,
  });

  final DetailCatalogUpdateOutcomeCode code;
  final DetailCatalogInputErrorCode? inputErrorCode;
  final String? expectedHost;
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
