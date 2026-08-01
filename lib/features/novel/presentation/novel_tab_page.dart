import 'package:flutter/material.dart';
import 'package:y300/features/novel/presentation/novel_shelf_page.dart';

/// 小说 Tab 容器。
class NovelTabPage extends StatelessWidget {
  const NovelTabPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return NovelShelfPage(isActive: isActive);
  }
}
