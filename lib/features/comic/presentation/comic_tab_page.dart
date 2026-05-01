import 'package:flutter/material.dart';
import 'package:y300/features/comic/presentation/comic_shelf_page.dart';

/// 漫画 Tab 容器，当前承载书架页与后续详情/阅读导航入口。
class ComicTabPage extends StatelessWidget {
  const ComicTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComicShelfPage();
  }
}
