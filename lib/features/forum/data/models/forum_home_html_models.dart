import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';

class ForumHomeHtmlData {
  const ForumHomeHtmlData({
    this.carouselItems = const <ForumHomeCarouselItem>[],
    this.sections = const <ForumHomeHtmlSection>[],
  });

  final List<ForumHomeCarouselItem> carouselItems;
  final List<ForumHomeHtmlSection> sections;

  bool get hasFavoriteSection {
    return sections.any((section) => section.isFavoriteSection);
  }
}

class ForumHomeHtmlSection {
  const ForumHomeHtmlSection({
    required this.title,
    required this.items,
    required this.isFavoriteSection,
    this.isInitiallyCollapsed = false,
  });

  final String title;
  final List<ForumHomeHtmlForumItem> items;
  final bool isFavoriteSection;
  final bool isInitiallyCollapsed;
}

class ForumHomeHtmlForumItem {
  const ForumHomeHtmlForumItem({
    required this.fid,
    required this.title,
    required this.description,
    required this.todayPosts,
    required this.url,
    this.iconUrl,
  });

  final String fid;
  final String title;
  final String description;
  final int todayPosts;
  final String url;
  final String? iconUrl;
}
