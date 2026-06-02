import 'package:flutter/widgets.dart';

// 阶段 0 契约冻结（书架多选与取消收藏方案）。
//
// 每个书架模块通过该可选能力接口声明「多选状态下能执行哪些操作」，
// UI 按声明渲染底部操作栏，新增模块无需改 UI。沿用项目既有的
// `ShelfModuleActionAdapter` / `ShelfSnapshotAdapter` 「可选能力接口」模式。
//
// 适配器是薄编排：runSelectionAction 内部委托给对应 use case
// （取消收藏 / 批量已读 / 下载 / 设置分类），不写业务规则。

/// 一个多选批量操作的声明（命令模式的元数据）。
class SelectionAction {
  const SelectionAction({
    required this.id,
    required this.icon,
    required this.label,
    this.destructive = false,
    this.needsConfirm = false,
  });

  /// 稳定标识，UI 通过它回调 [ShelfSelectionActionAdapter.runSelectionAction]。
  final String id;

  /// 操作栏按钮图标。
  final IconData icon;

  /// 无障碍标签 / 提示文案。
  final String label;

  /// 破坏性操作（如取消收藏会清除作品），UI 需特殊视觉与错误提示。
  final bool destructive;

  /// 执行前需要二次确认弹窗。
  final bool needsConfirm;
}

/// 批量操作执行结果。
///
/// 用结构化结果代替「抛异常 / 静默成功」，让 UI 能报告部分失败
/// （例如取消收藏时部分 tid 删除失败）。
class SelectionActionResult {
  const SelectionActionResult({
    required this.message,
    this.changed = false,
    this.failedCount = 0,
  });

  /// 给用户的反馈文案（SnackBar）。
  final String message;

  /// 是否产生了数据变更（决定是否触发书架 reload）。
  final bool changed;

  /// 失败条目数（部分失败时 > 0）。
  final int failedCount;

  bool get hasFailure => failedCount > 0;
}

/// 书架模块的多选操作能力。模块按需实现；不实现则该模块不支持多选操作。
abstract class ShelfSelectionActionAdapter {
  /// 该模块在多选状态下暴露的操作集合（决定操作栏按钮）。
  List<SelectionAction> get selectionActions;

  /// 执行某个批量操作。
  ///
  /// [workIds] 是当前选中集合（收藏页为 `favorite:tid` 形态，适配器内部
  /// 自行换算到 tid 级用例）。
  Future<SelectionActionResult> runSelectionAction({
    required String actionId,
    required Set<String> workIds,
  });
}

/// 多选操作的标准 id 常量，避免各模块各写字符串字面量。
class SelectionActionIds {
  const SelectionActionIds._();

  static const String assignCategory = 'assign-category';
  static const String markAllRead = 'mark-all-read';
  static const String markAllUnread = 'mark-all-unread';
  static const String download = 'download';
  static const String unfavorite = 'unfavorite';
}
