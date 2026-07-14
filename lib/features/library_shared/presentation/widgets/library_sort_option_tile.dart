import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// 书架与作品详情共用的排序选项行。
class LibrarySortOptionTile extends StatelessWidget {
  const LibrarySortOptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.direction,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final LibrarySortDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        selected && direction == LibrarySortDirection.asc
            ? Icons.arrow_upward
            : Icons.arrow_downward,
        size: 18,
      ),
      title: Text(label),
      trailing: selected ? const Icon(Icons.check, size: 18) : null,
      onTap: onTap,
    );
  }
}
