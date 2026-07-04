import 'package:flutter/material.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/presentation/widgets/composer_anchored_dropdown.dart';

/// 主题分类选择器。
///
/// 行为：
/// - `types` 为空时整个 widget 隐藏（部分版块没有主题分类）。
/// - 必选分类可渲染成下拉菜单，不把选项铺进正文空间。
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
    this.useDropdown = false,
  });

  final List<ThreadType> types;
  final bool typeRequired;
  final String? selectedTypeId;
  final ValueChanged<String?> onSelected;
  final bool enabled;
  final Key? containerKey;
  final Key Function(ThreadType type)? chipKeyBuilder;

  /// "无分类"项的 widget key——仅在 `typeRequired == false` 时存在。
  final Key? noneChipKey;
  final Key? toggleKey;
  final Key? summaryKey;
  final bool useDropdown;

  ThreadType? get _selectedType {
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
    final title = typeRequired ? '主题分类（必选）' : '主题分类';
    final selectedLabel = _selectedType?.name ?? (typeRequired ? '未选择' : '无分类');
    if (useDropdown) {
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

    final theme = Theme.of(context);
    return Column(
      key: containerKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (!typeRequired)
              ChoiceChip(
                key: noneChipKey,
                label: const Text('无分类'),
                selected: selectedTypeId == null,
                onSelected: enabled ? (_) => onSelected(null) : null,
              ),
            for (final type in types)
              ChoiceChip(
                key: chipKeyBuilder?.call(type),
                label: Text(type.name),
                selected: selectedTypeId == type.id,
                onSelected: enabled ? (_) => onSelected(type.id) : null,
              ),
          ],
        ),
      ],
    );
  }
}
