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

  /// 顶部标题文案，如“漫画”“小说”。
  String get moduleTitle;

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
  Future<List<LibraryWorkItem>> loadCategoryItems({
    required String categoryId,
  });

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
  Future<Object> buildDetailRouteArgument({
    required String workId,
  });

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

  /// 更新显示偏好。
  Future<void> updateDisplayPreference({
    required LibraryDisplayMode displayMode,
    required int gridColumnCount,
  });

  /// 读取显示偏好。
  Future<LibraryDisplayPreference> loadDisplayPreference();

  /// 随机打开一个作品（more 菜单行为）。
  Future<String?> pickRandomWorkId({
    required String categoryId,
  });
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

class ShelfModuleActionResult {
  const ShelfModuleActionResult({
    required this.message,
    this.changed = false,
  });

  final String message;
  final bool changed;
}

abstract class ShelfModuleActionAdapter {
  List<LibraryShelfMenuAction> get menuActions;

  Future<ShelfModuleActionResult> runMenuAction(String actionId);
}

class LibraryShelfMenuAction {
  const LibraryShelfMenuAction({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class LibraryShelfTaskProgress {
  const LibraryShelfTaskProgress({
    required this.message,
    this.current = 0,
    this.total,
    this.active = true,
  });

  final String message;
  final int current;
  final int? total;
  final bool active;

  double? get fraction {
    final resolvedTotal = total;
    if (resolvedTotal == null || resolvedTotal <= 0) {
      return null;
    }
    return (current / resolvedTotal).clamp(0.0, 1.0).toDouble();
  }
}

/// 统一显示偏好。
class LibraryDisplayPreference {
  const LibraryDisplayPreference({
    required this.displayMode,
    required this.gridColumnCount,
  });

  final LibraryDisplayMode displayMode;
  final int gridColumnCount;

  static const LibraryDisplayPreference defaults = LibraryDisplayPreference(
    displayMode: LibraryDisplayMode.grid,
    gridColumnCount: 3,
  );
}
