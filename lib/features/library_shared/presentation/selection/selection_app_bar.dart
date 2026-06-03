import 'package:flutter/material.dart';

class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionAppBar({
    super.key,
    required this.selectedCount,
    required this.onClose,
    required this.onSelectAll,
    required this.onInvertSelection,
  });

  final int selectedCount;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onInvertSelection;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      key: const Key('selection-app-bar'),
      leading: IconButton(
        key: const Key('selection-app-bar-close'),
        tooltip: '退出多选',
        icon: const Icon(Icons.close),
        onPressed: onClose,
      ),
      title: Text(
        '已选 $selectedCount 项',
        key: const Key('selection-app-bar-title'),
      ),
      actions: [
        IconButton(
          key: const Key('selection-app-bar-select-all'),
          tooltip: '全选当前分类',
          icon: const Icon(Icons.select_all),
          onPressed: onSelectAll,
        ),
        IconButton(
          key: const Key('selection-app-bar-invert'),
          tooltip: '反选当前分类',
          icon: const Icon(Icons.flip_to_back),
          onPressed: onInvertSelection,
        ),
      ],
    );
  }
}
