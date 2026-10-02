import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/posting/presentation/widgets/composer_anchored_dropdown.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 主题分类选择器。
///
/// 行为：
/// - `types` 为空时整个 widget 隐藏（部分版块没有主题分类）。
/// - 始终使用下拉菜单，不把选项铺进正文空间。
/// - `typeRequired == false` 时第一项是"无分类"，对应 `typeId == null`。
class ThreadTypeSelector extends StatelessWidget {
  const ThreadTypeSelector({
    super.key,
    required this.types,
    required this.typeRequired,
    required this.selectedTypeId,
    required this.onSelected,
    this.enabled = true,
    this.containerKey,
    this.chipKeyBuilder,
    this.noneChipKey,
    this.toggleKey,
    this.summaryKey,
  });

  final List<ThreadCreationType> types;
  final bool typeRequired;
  final String? selectedTypeId;
  final ValueChanged<String?> onSelected;
  final bool enabled;
  final Key? containerKey;
  final Key Function(ThreadCreationType type)? chipKeyBuilder;

  /// "无分类"项的 widget key——仅在 `typeRequired == false` 时存在。
  final Key? noneChipKey;
  final Key? toggleKey;
  final Key? summaryKey;

  ThreadCreationType? get _selectedType {
    final selectedTypeId = this.selectedTypeId;
    if (selectedTypeId == null) {
      return null;
    }
    for (final type in types) {
      if (type.id == selectedTypeId) {
        return type;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final title = typeRequired ? l10n.postingTypeRequired : l10n.postingType;
    final selectedLabel =
        _selectedType?.name ??
        (typeRequired ? l10n.postingTypeUnselected : l10n.postingTypeNone);
    return SizedBox(
      key: containerKey,
      width: double.infinity,
      child: ComposerAnchoredDropdown<String?>(
        anchorKey: toggleKey,
        summaryKey: summaryKey,
        label: title,
        value: selectedTypeId,
        valueLabelBuilder: (_) => selectedLabel,
        items: [
          if (!typeRequired)
            ComposerDropdownItem<String?>(
              key: noneChipKey,
              value: null,
              label: l10n.postingTypeNone,
            ),
          for (final type in types)
            ComposerDropdownItem<String?>(
              key: chipKeyBuilder?.call(type),
              value: type.id,
              label: type.name,
            ),
        ],
        onSelected: onSelected,
        enabled: enabled,
      ),
    );
  }
}
