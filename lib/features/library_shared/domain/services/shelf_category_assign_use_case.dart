// 阶段 0 契约冻结（书架多选与取消收藏方案）。
//
// 批量设置分类用例：把多选选中作品移动到目标分类（已有或新建）。
// 内部对每个 workId 调用模块 repository 的 moveWorkToCategory。
// 实现落在阶段 5（适配器内委托），此处仅冻结对外签名。

/// 批量设置分类结果。
class ShelfCategoryAssignResult {
  const ShelfCategoryAssignResult({
    required this.assignedWorkIds,
    required this.failedWorkIds,
    required this.targetCategoryId,
  });

  final List<String> assignedWorkIds;
  final List<String> failedWorkIds;
  final String targetCategoryId;

  bool get hasFailure => failedWorkIds.isNotEmpty;
}

/// 批量把选中作品移动到目标分类。
abstract class ShelfCategoryAssignUseCase {
  Future<ShelfCategoryAssignResult> assign({
    required Set<String> workIds,
    required String targetCategoryId,
  });
}
