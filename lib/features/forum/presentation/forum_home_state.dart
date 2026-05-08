import 'package:y300/features/forum/data/models/forum_index_models.dart';

enum ForumSectionType { regular }

/// 论坛首页中一个可展示分组，通常对应一个分类
class ForumSection {
  ForumSection({
    required this.title,
    required this.items,
    this.type = ForumSectionType.regular,
  });

  final String title;
  final List<ForumItem> items;
  final ForumSectionType type;
}

/// 首页渲染模型，避免页面直接依赖后端原始结构
class ForumHomeViewData {
  ForumHomeViewData({required this.sections, required this.isLoggedIn});

  final List<ForumSection> sections;
  final bool isLoggedIn;

  int get sectionCount => sections.length;

  int get forumCount =>
      sections.fold<int>(0, (sum, section) => sum + section.items.length);
}
