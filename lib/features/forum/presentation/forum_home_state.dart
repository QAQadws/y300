import 'package:y300/features/forum/data/models/forum_index_models.dart';

/// 论坛首页中一个可展示分组，通常对应一个分类
class ForumSection {
  ForumSection({required this.title, required this.items});

  final String title;
  final List<ForumItem> items;
}

/// 首页渲染模型，避免页面直接依赖后端原始结构
class ForumHomeViewData {
  ForumHomeViewData({required this.sections});

  final List<ForumSection> sections;

  int get sectionCount => sections.length;

  int get forumCount => sections.fold<int>(
    0,
    (sum, section) => sum + section.items.length,
  );
}
