import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';

enum ForumSectionType { regular, favorite }

/// 论坛首页中一个可展示分组，通常对应一个分类
class ForumSection {
  const ForumSection({
    required this.title,
    this.items = const <ForumItem>[],
    this.favoriteItems = const <FavoriteForum>[],
    this.type = ForumSectionType.regular,
  });

  final String title;
  final List<ForumItem> items;
  final List<FavoriteForum> favoriteItems;
  final ForumSectionType type;
}

/// 首页渲染模型，避免页面直接依赖后端原始结构
class ForumHomeViewData {
  ForumHomeViewData({required this.sections, required this.isLoggedIn});

  final List<ForumSection> sections;
  final bool isLoggedIn;

  int get sectionCount => sections.length;

  int get regularForumCount =>
      sections.fold<int>(0, (sum, section) => sum + section.items.length);

  int get forumCount {
    final countedFids = <String>{};
    var count = 0;
    for (final section in sections) {
      for (final item in section.items) {
        if (countedFids.add(item.fid)) {
          count++;
        }
      }
      for (final item in section.favoriteItems) {
        if (countedFids.add(item.fid)) {
          count++;
        }
      }
    }
    return count;
  }
}
