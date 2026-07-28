import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

/// 统一书架页模块适配合同。
///
/// 设计原则：
/// 1. 统一页负责“交互编排与状态机”；
/// 2. 适配器负责“模块差异数据读写”；
/// 3. 合同只暴露必要能力，防止 shared 层反向依赖具体模块实现。
abstract class ShelfModuleAdapter {
  /// 当前适配器对应模块。
  LibraryModuleKey get moduleKey;

  /// 默认显示模式：漫画通常网格，小说通常列表。
  LibraryDisplayMode get defaultDisplayMode;

  /// 可选的长任务进度。默认没有进度源，收藏等模块可按需接入。
  ValueListenable<LibraryShelfTaskProgress?>? get taskProgress => null;

  /// 可选的后台数据刷新信号。后台服务写入章节、封面或收藏分类后，
  /// 统一控制器据此重新读取本地快照。
  ValueListenable<LibraryShelfRefreshSignal?>? get shelfRefreshSignals => null;

  /// 加载分类列表。
  Future<List<LibraryCategory>> loadCategories();

  /// 加载指定分类的作品。
  Future<List<LibraryWorkItem>> loadCategoryItems({required String categoryId});

  /// 按关键词搜索（作品名/作者/汉化组等模块定义字段）。
  Future<Map<String, List<LibraryWorkItem>>> searchItemsByKeyword({
    required String keyword,
  });

  /// 根据筛选与排序查询分类作品。
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  });

  /// 刷新书架。
  Future<void> refreshShelf();

  /// 进入详情页时使用的路由目标（统一页不关心具体 Route 类型）。
  Future<Object> buildDetailRouteArgument({required String workId});

  /// 分类管理。
  Future<String> createCategory({required String name});

  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  });

  Future<void> deleteCategory({required String categoryId});

  /// 移动作品到目标分类。
  Future<void> moveWorkToCategory({
    required String workId,
    required String fromCategoryId,
    required String toCategoryId,
  });

  /// 随机打开一个作品（more 菜单行为）。
  Future<String?> pickRandomWorkId({required String categoryId});
}

class ShelfModuleCapabilities {
  const ShelfModuleCapabilities({
    this.supportsReadState = true,
    this.supportsBookmarkFilter = false,
    this.defaultSortOption = LibraryShelfSortOption.defaults,
  });

  const ShelfModuleCapabilities.defaults()
    : supportsReadState = true,
      supportsBookmarkFilter = false,
      defaultSortOption = LibraryShelfSortOption.defaults;

  final bool supportsReadState;
  final bool supportsBookmarkFilter;
  final LibraryShelfSortOption defaultSortOption;

  List<LibraryShelfSortField> get availableSortFields =>
      <LibraryShelfSortField>[
        LibraryShelfSortField.chapterCount,
        if (supportsReadState) LibraryShelfSortField.unreadCount,
        LibraryShelfSortField.favoriteAddedAt,
      ];

  LibraryFilterSet normalizeFilters(LibraryFilterSet filters) {
    return filters.copyWith(
      unread: supportsReadState ? filters.unread : TriStateFilterValue.ignore,
      read: supportsReadState ? filters.read : TriStateFilterValue.ignore,
      hasTags: TriStateFilterValue.ignore,
      bookmarked: supportsBookmarkFilter
          ? filters.bookmarked
          : TriStateFilterValue.ignore,
    );
  }

  LibraryShelfSortOption normalizeSortOption(LibraryShelfSortOption option) {
    return availableSortFields.contains(option.field)
        ? option
        : defaultSortOption;
  }
}

abstract interface class ShelfModuleCapabilitiesAdapter {
  ShelfModuleCapabilities get capabilities;
}

ShelfModuleCapabilities resolveShelfModuleCapabilities(
  ShelfModuleAdapter adapter,
) {
  return adapter is ShelfModuleCapabilitiesAdapter
      ? (adapter as ShelfModuleCapabilitiesAdapter).capabilities
      : const ShelfModuleCapabilities.defaults();
}

/// 可选的聚合快照能力。
///
/// 支持该合同的模块可以把分类、筛选后作品、命中数量一次性返回给控制器。
/// 不支持的模块仍会走旧的 `loadCategories + queryItems` 回退路径。
abstract class ShelfSnapshotAdapter {
  Future<LibraryShelfSnapshot> querySnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  });
}

/// 书架作品拥有独立下载状态时实现的标记能力。
///
/// 统一书架据此展示“已下载”筛选；水合内容天然可离线的模块无需实现。
abstract interface class ShelfDownloadStatusAdapter {}

enum LibraryShelfMenuAction { mergeDuplicates }

enum ShelfModuleActionOutcomeCode { success, noChange, unsupported }

class ShelfModuleActionOutcome {
  const ShelfModuleActionOutcome({
    required this.code,
    this.changed = false,
    this.affectedCount = 0,
  });

  final ShelfModuleActionOutcomeCode code;
  final bool changed;
  final int affectedCount;
}

abstract class ShelfModuleActionAdapter {
  List<LibraryShelfMenuAction> get menuActions;

  Future<ShelfModuleActionOutcome> runMenuAction(LibraryShelfMenuAction action);
}

enum LibraryShelfTaskProgressCode {
  coverWarmup,
  favoriteSyncFetching,
  favoriteSyncSaving,
  favoriteSyncLoadingDetails,
  favoriteSyncFinishing,
  comicSearchWaiting,
}

class LibraryShelfTaskProgress {
  const LibraryShelfTaskProgress({
    required this.code,
    this.subject,
    this.estimatedDuration,
    this.current = 0,
    this.total,
    this.active = true,
    this.source,
    this.visible = true,
    this.reloadOnCompletion = true,
  });

  final LibraryShelfTaskProgressCode code;

  /// Raw server/user content used only as a presentation placeholder.
  final String? subject;
  final Duration? estimatedDuration;
  final int current;
  final int? total;
  final bool active;
  final LibraryMutationSource? source;
  final bool visible;
  final bool reloadOnCompletion;

  double? get fraction {
    final resolvedTotal = total;
    if (resolvedTotal == null || resolvedTotal <= 0) {
      return null;
    }
    return (current / resolvedTotal).clamp(0.0, 1.0).toDouble();
  }
}
