import 'package:y300/core/utils/parse_utils.dart';

class ForumCategory {
  ForumCategory({required this.fid, required this.name, required this.forums});

  final String fid;
  final String name;
  final List<String> forums;

  factory ForumCategory.fromJson(JsonMap json) {
    return ForumCategory(
      fid: ParseUtils.asString(json['fid']),
      name: ParseUtils.asString(json['name']),
      forums: ParseUtils.asList(
        json['forums'],
      ).map((item) => item.toString()).toList(),
    );
  }
}

class ForumItem {
  ForumItem({
    required this.fid,
    required this.name,
    required this.threads,
    required this.posts,
    required this.todayPosts,
    required this.description,
    required this.icon,
    required this.subForums,
  });

  final String fid;
  final String name;
  final int threads;
  final int posts;
  final int todayPosts;
  final String description;
  final String icon;
  final List<ForumItem> subForums;

  factory ForumItem.fromJson(JsonMap json) {
    return ForumItem(
      fid: ParseUtils.asString(json['fid']),
      name: ParseUtils.asString(json['name']),
      threads: ParseUtils.asInt(json['threads']),
      posts: ParseUtils.asInt(json['posts']),
      todayPosts: ParseUtils.asInt(json['todayposts']),
      description: ParseUtils.asString(json['description']),
      icon: ParseUtils.asString(json['icon']),
      subForums: ParseUtils.asList(
        json['sublist'],
      ).map((item) => ForumItem.fromJson(ParseUtils.asMap(item))).toList(),
    );
  }
}

class ForumIndexData {
  ForumIndexData({required this.categories, required this.forums});

  final List<ForumCategory> categories;
  final List<ForumItem> forums;

  factory ForumIndexData.fromVariables(JsonMap variables) {
    return ForumIndexData(
      categories: ParseUtils.asList(
        variables['catlist'],
      ).map((item) => ForumCategory.fromJson(ParseUtils.asMap(item))).toList(),
      forums: ParseUtils.asList(
        variables['forumlist'],
      ).map((item) => ForumItem.fromJson(ParseUtils.asMap(item))).toList(),
    );
  }
}
