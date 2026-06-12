import 'package:flutter/material.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';

/// 主题分类选择器（ChoiceChip 实现）。
///
/// 行为：
/// - `types` 为空时整个 widget 隐藏（部分版块没有主题分类）。
/// - `typeRequired == true` 时不展示"无分类"项；用户必须从列表里挑一个，
///   否则 controller 的 preflight 会拦住提交。
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

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Column(
      key: containerKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          typeRequired ? '主题分类（必选）' : '主题分类',
          style: theme.textTheme.titleSmall,
        ),
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
