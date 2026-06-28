import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';

class ForumHomeSnapshotCodec implements SnapshotCodec<ForumHomePayload> {
  const ForumHomeSnapshotCodec();

  @override
  String get snapshotType => CacheKeyCanonicalizer.forumHomeSnapshotType;

  @override
  int get codecVersion => 1;

  @override
  int get parserVersion => 1;

  @override
  Object? encode(ForumHomePayload value) {
    return <String, Object?>{
      'isLoggedIn': value.isLoggedIn,
      'forumIndex': _encodeForumIndex(value.forumIndex),
      'favoriteForums': value.favoriteForums
          .map(_encodeFavoriteForum)
          .toList(growable: false),
      'chromeData': _encodeChromeData(value.chromeData),
    };
  }

  @override
  ForumHomePayload decode(Object? json) {
    final map = ParseUtils.asMap(json);
    return ForumHomePayload(
      forumIndex: _decodeForumIndex(map['forumIndex']),
      isLoggedIn: ParseUtils.asBool(map['isLoggedIn']),
      favoriteForums: ParseUtils.asList(map['favoriteForums'])
          .map((item) => _decodeFavoriteForum(ParseUtils.asMap(item)))
          .toList(growable: false),
      chromeData: _decodeChromeData(map['chromeData']),
    );
  }

  Map<String, Object?> _encodeForumIndex(ForumIndexData value) {
    return <String, Object?>{
      'categories': value.categories
          .map(_encodeForumCategory)
          .toList(growable: false),
      'forums': value.forums.map(_encodeForumItem).toList(growable: false),
    };
  }

  ForumIndexData _decodeForumIndex(Object? value) {
    final map = ParseUtils.asMap(value);
    return ForumIndexData(
      categories: ParseUtils.asList(map['categories'])
          .map((item) => _decodeForumCategory(ParseUtils.asMap(item)))
          .toList(growable: false),
      forums: ParseUtils.asList(map['forums'])
          .map((item) => _decodeForumItem(ParseUtils.asMap(item)))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodeForumCategory(ForumCategory value) {
    return <String, Object?>{
      'fid': value.fid,
      'name': value.name,
      'forums': value.forums,
    };
  }

  ForumCategory _decodeForumCategory(Map<String, dynamic> map) {
    return ForumCategory(
      fid: ParseUtils.asString(map['fid']),
      name: ParseUtils.asString(map['name']),
      forums: ParseUtils.asList(
        map['forums'],
      ).map((value) => value.toString()).toList(growable: false),
    );
  }

  Map<String, Object?> _encodeForumItem(ForumItem value) {
    return <String, Object?>{
      'fid': value.fid,
      'name': value.name,
      'threads': value.threads,
      'posts': value.posts,
      'todayPosts': value.todayPosts,
      'description': value.description,
      'icon': value.icon,
      'subForums': value.subForums
          .map(_encodeForumItem)
          .toList(growable: false),
    };
  }

  ForumItem _decodeForumItem(Map<String, dynamic> map) {
    return ForumItem(
      fid: ParseUtils.asString(map['fid']),
      name: ParseUtils.asString(map['name']),
      threads: ParseUtils.asInt(map['threads']),
      posts: ParseUtils.asInt(map['posts']),
      todayPosts: ParseUtils.asInt(map['todayPosts']),
      description: ParseUtils.asString(map['description']),
      icon: ParseUtils.asString(map['icon']),
      subForums: ParseUtils.asList(map['subForums'])
          .map((item) => _decodeForumItem(ParseUtils.asMap(item)))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodeFavoriteForum(FavoriteForum value) {
    return <String, Object?>{
      'favid': value.favid,
      'fid': value.fid,
      'title': value.title,
      'description': value.description,
      'threads': value.threads,
      'posts': value.posts,
      'todayPosts': value.todayPosts,
    };
  }

  FavoriteForum _decodeFavoriteForum(Map<String, dynamic> map) {
    return FavoriteForum(
      favid: ParseUtils.asString(map['favid']),
      fid: ParseUtils.asString(map['fid']),
      title: ParseUtils.asString(map['title']),
      description: ParseUtils.asString(map['description']),
      threads: ParseUtils.asInt(map['threads']),
      posts: ParseUtils.asInt(map['posts']),
      todayPosts: ParseUtils.asInt(map['todayPosts']),
    );
  }

  Map<String, Object?> _encodeChromeData(ForumHomeChromeData value) {
    return <String, Object?>{
      'carouselItems': value.carouselItems
          .map(_encodeCarouselItem)
          .toList(growable: false),
      'favoriteForums': value.favoriteForums
          .map(_encodeChromeForum)
          .toList(growable: false),
    };
  }

  ForumHomeChromeData _decodeChromeData(Object? value) {
    final map = ParseUtils.asMap(value);
    return ForumHomeChromeData(
      carouselItems: ParseUtils.asList(map['carouselItems'])
          .map((item) => _decodeCarouselItem(ParseUtils.asMap(item)))
          .toList(growable: false),
      favoriteForums: ParseUtils.asList(map['favoriteForums'])
          .map((item) => _decodeChromeForum(ParseUtils.asMap(item)))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodeCarouselItem(ForumHomeCarouselItem value) {
    return <String, Object?>{
      'imageUrl': value.imageUrl,
      'targetUrl': value.targetUrl,
      'aspectRatio': value.aspectRatio,
    };
  }

  ForumHomeCarouselItem _decodeCarouselItem(Map<String, dynamic> map) {
    return ForumHomeCarouselItem(
      imageUrl: ParseUtils.asString(map['imageUrl']),
      targetUrl: ParseUtils.asString(map['targetUrl']),
      aspectRatio: _nullableDouble(map['aspectRatio']),
    );
  }

  Map<String, Object?> _encodeChromeForum(ForumHomeChromeForumItem value) {
    return <String, Object?>{
      'fid': value.fid,
      'title': value.title,
      'description': value.description,
      'todayPosts': value.todayPosts,
    };
  }

  ForumHomeChromeForumItem _decodeChromeForum(Map<String, dynamic> map) {
    return ForumHomeChromeForumItem(
      fid: ParseUtils.asString(map['fid']),
      title: ParseUtils.asString(map['title']),
      description: ParseUtils.asString(map['description']),
      todayPosts: ParseUtils.asInt(map['todayPosts']),
    );
  }

  double? _nullableDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
