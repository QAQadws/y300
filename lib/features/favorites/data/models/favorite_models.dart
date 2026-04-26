import 'package:y300/core/utils/parse_utils.dart';

class FavoriteForum {
  FavoriteForum({
    required this.favid,
    required this.fid,
    required this.title,
    required this.description,
    required this.threads,
    required this.posts,
    required this.todayPosts,
  });

  final String favid;
  final String fid;
  final String title;
  final String description;
  final int threads;
  final int posts;
  final int todayPosts;

  factory FavoriteForum.fromJson(JsonMap json) {
    return FavoriteForum(
      favid: ParseUtils.asString(json['favid']),
      fid: ParseUtils.asString(json['id']),
      title: ParseUtils.asString(json['title']),
      description: ParseUtils.asString(json['description']),
      threads: ParseUtils.asInt(json['threads']),
      posts: ParseUtils.asInt(json['posts']),
      todayPosts: ParseUtils.asInt(json['todayposts']),
    );
  }
}

class FavoriteThread {
  FavoriteThread({
    required this.favid,
    required this.tid,
    required this.title,
    required this.description,
    required this.author,
    required this.replies,
    required this.url,
    required this.dateline,
  });

  final String favid;
  final String tid;
  final String title;
  final String description;
  final String author;
  final int replies;
  final String url;
  final int dateline;

  factory FavoriteThread.fromJson(JsonMap json) {
    return FavoriteThread(
      favid: ParseUtils.asString(json['favid']),
      tid: ParseUtils.asString(json['id']),
      title: ParseUtils.asString(json['title']),
      description: ParseUtils.asString(json['description']),
      author: ParseUtils.asString(json['author']),
      replies: ParseUtils.asInt(json['replies']),
      url: ParseUtils.asString(json['url']),
      dateline: ParseUtils.asInt(json['dateline']),
    );
  }
}

class FavoriteThreadsPage {
  FavoriteThreadsPage({
    required this.page,
    required this.perPage,
    required this.totalCount,
    required this.items,
  });

  final int page;
  final int perPage;
  final int totalCount;
  final List<FavoriteThread> items;

  /// 根据 totalCount 粗略判断是否还有下一页。
  bool get hasMore => page * perPage < totalCount;

  factory FavoriteThreadsPage.fromVariables(
    JsonMap variables, {
    required int page,
  }) {
    return FavoriteThreadsPage(
      page: page,
      perPage: ParseUtils.asInt(variables['perpage'], fallback: 20),
      totalCount: ParseUtils.asInt(variables['count']),
      items: ParseUtils.asList(
        variables['list'],
      ).map((item) => FavoriteThread.fromJson(ParseUtils.asMap(item))).toList(),
    );
  }
}
