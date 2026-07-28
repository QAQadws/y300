import 'package:flutter/widgets.dart';

/// 书架批量操作声明。
class SelectionAction {
  const SelectionAction({
    required this.id,
    required this.icon,
    this.destructive = false,
    this.needsConfirm = false,
    @Deprecated('Use presentation localization by action id.') this.label,
  });

  final String id;
  final IconData icon;
  final bool destructive;
  final bool needsConfirm;

  /// Compatibility field for adapters that have not migrated yet.
  ///
  /// Shared presentation must resolve labels from [id] and AppLocalizations.
  @Deprecated('Use presentation localization by action id.')
  final String? label;
}

enum SelectionActionResultCode {
  legacyMessage,
  success,
  partialFailure,
  unsupported,
  missingTargetCategory,
  noValidItems,
  noChange,
}

/// 书架批量操作执行结果。
class SelectionActionResult {
  const SelectionActionResult({
    this.code = SelectionActionResultCode.legacyMessage,
    this.message,
    this.changed = false,
    this.succeededCount = 0,
    this.failedCount = 0,
    this.enqueuedCount = 0,
    this.deduplicatedCount = 0,
  });

  final SelectionActionResultCode code;

  /// Compatibility field for pre-localization adapters.
  @Deprecated('Use code and numeric result fields.')
  final String? message;
  final bool changed;
  final int succeededCount;
  final int failedCount;
  final int enqueuedCount;
  final int deduplicatedCount;

  bool get hasFailure =>
      failedCount > 0 || code == SelectionActionResultCode.partialFailure;
}

/// 一次批量操作请求。
///
/// [activeCategoryId] 表示当前可见分类页；批量改分类时它就是来源分类。
/// [targetCategoryId] 仅在 `assign-category` 场景下使用。
class SelectionActionExecutionRequest {
  const SelectionActionExecutionRequest({
    required this.actionId,
    required this.workIds,
    required this.activeCategoryId,
    this.targetCategoryId,
  });

  final String actionId;
  final Set<String> workIds;
  final String activeCategoryId;
  final String? targetCategoryId;
}

/// 书架模块的批量操作能力。
abstract class ShelfSelectionActionAdapter {
  List<SelectionAction> get selectionActions;

  Future<SelectionActionResult> runSelectionAction(
    SelectionActionExecutionRequest request,
  );
}

/// 批量动作稳定 id。
class SelectionActionIds {
  const SelectionActionIds._();

  static const String assignCategory = 'assign-category';
  static const String markAllRead = 'mark-all-read';
  static const String markAllUnread = 'mark-all-unread';
  static const String download = 'download';
  static const String unfavorite = 'unfavorite';
}
