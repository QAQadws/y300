import 'package:flutter/material.dart';

/// 书架页面通用 AppBar。
///
/// 统一标题、搜索入口和“菜单动作”承载结构，业务仅传入菜单定义与处理逻辑。
class ShelfAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShelfAppBar({
    super.key,
    required this.title,
    this.searchTooltip = '搜索',
    this.menuTooltip = '菜单',
    this.onSearchTap,
    this.onMenuSelected,
    this.menuItems = const <PopupMenuEntry<String>>[],
  });

  final String title;
  final String searchTooltip;
  final String menuTooltip;
  final VoidCallback? onSearchTap;
  final ValueChanged<String>? onMenuSelected;
  final List<PopupMenuEntry<String>> menuItems;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      actions: [
        IconButton(
          tooltip: searchTooltip,
          icon: const Icon(Icons.search),
          onPressed: onSearchTap,
        ),
        PopupMenuButton<String>(
          tooltip: menuTooltip,
          onSelected: onMenuSelected,
          itemBuilder: (context) => menuItems,
        ),
      ],
    );
  }
}
