import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

class ForumDisplaySnapshotCodec implements SnapshotCodec<ForumDisplayData> {
  const ForumDisplaySnapshotCodec();

  @override
  String get snapshotType => CacheKeyCanonicalizer.forumDisplaySnapshotType;

  @override
  int get codecVersion => 1;

  @override
  int get parserVersion => 1;

  @override
  Object? encode(ForumDisplayData value) {
    return <String, Object?>{
      'fid': value.fid,
      'forumName': value.forumName,
      'currentPage': value.currentPage,
      'perPage': value.perPage,
      'totalThreads': value.totalThreads,
      'headImageUrl': value.headImageUrl,
      'forumIconUrl': value.forumIconUrl,
      'todayPosts': value.todayPosts,
      'rank': value.rank,
      'postUrl': value.postUrl,
      'searchUrl': value.searchUrl,
      'favoriteUrl': value.favoriteUrl,
      'previousPageUrl': value.previousPageUrl,
      'nextPageUrl': value.nextPageUrl,
      'lastPage': value.lastPage,
      'hasMoreOverride': value.hasMoreOverride,
      'threads': value.threads.map(_encodeThread).toList(growable: false),
      'primaryFilters': value.primaryFilters
          .map(_encodeFilter)
          .toList(growable: false),
      'typeFilters': value.typeFilters
          .map(_encodeFilter)
          .toList(growable: false),
      'subForums': value.subForums.map(_encodeSubForum).toList(growable: false),
      'topEntries': value.topEntries
          .map(_encodeTopEntry)
          .toList(growable: false),
    };
  }

  @override
  ForumDisplayData decode(Object? json) {
    final map = ParseUtils.asMap(json);
    return ForumDisplayData(
      fid: ParseUtils.asString(map['fid']),
      forumName: ParseUtils.asString(map['forumName']),
      currentPage: ParseUtils.asInt(map['currentPage'], fallback: 1),
      perPage: ParseUtils.asInt(map['perPage'], fallback: 20),
      totalThreads: ParseUtils.asInt(map['totalThreads']),
      headImageUrl: _nullableString(map['headImageUrl']),
      forumIconUrl: _nullableString(map['forumIconUrl']),
      todayPosts: ParseUtils.asInt(map['todayPosts']),
      rank: ParseUtils.asInt(map['rank']),
      postUrl: _nullableString(map['postUrl']),
      searchUrl: _nullableString(map['searchUrl']),
      favoriteUrl: _nullableString(map['favoriteUrl']),
      previousPageUrl: _nullableString(map['previousPageUrl']),
      nextPageUrl: _nullableString(map['nextPageUrl']),
      lastPage: _nullableInt(map['lastPage']),
      hasMoreOverride: _nullableBool(map['hasMoreOverride']),
      threads: ParseUtils.asList(map['threads'])
          .map((item) => _decodeThread(ParseUtils.asMap(item)))
          .toList(growable: false),
      primaryFilters: ParseUtils.asList(map['primaryFilters'])
          .map((item) => _decodeFilter(ParseUtils.asMap(item)))
          .toList(growable: false),
      typeFilters: ParseUtils.asList(map['typeFilters'])
          .map((item) => _decodeFilter(ParseUtils.asMap(item)))
          .toList(growable: false),
      subForums: ParseUtils.asList(map['subForums'])
          .map((item) => _decodeSubForum(ParseUtils.asMap(item)))
          .toList(growable: false),
      topEntries: ParseUtils.asList(map['topEntries'])
          .map((item) => _decodeTopEntry(ParseUtils.asMap(item)))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodeThread(ForumThreadSummary value) {
    return <String, Object?>{
      'tid': value.tid,
      'typeid': value.typeid,
      'sourceTagName': value.sourceTagName,
      'subject': value.subject,
      'author': value.author,
      'replies': value.replies,
      'views': value.views,
      'dateline': value.dateline,
      'uid': value.uid,
      'avatarUrl': value.avatarUrl,
      'authorUrl': value.authorUrl,
      'threadUrl': value.threadUrl,
      'excerpt': value.excerpt,
      'sourceTagUrl': value.sourceTagUrl,
      'badgeLabel': value.badgeLabel,
      'titleColorHex': value.titleColorHex,
      'isLocked': value.isLocked,
    };
  }

  ForumThreadSummary _decodeThread(Map<String, dynamic> map) {
    return ForumThreadSummary(
      tid: ParseUtils.asString(map['tid']),
      typeid: ParseUtils.asString(map['typeid']),
      sourceTagName: _nullableString(map['sourceTagName']),
      subject: ParseUtils.asString(map['subject']),
      author: ParseUtils.asString(map['author']),
      replies: ParseUtils.asInt(map['replies']),
      views: ParseUtils.asInt(map['views']),
      dateline: ParseUtils.asString(map['dateline']),
      uid: ParseUtils.asString(map['uid']),
      avatarUrl: _nullableString(map['avatarUrl']),
      authorUrl: _nullableString(map['authorUrl']),
      threadUrl: _nullableString(map['threadUrl']),
      excerpt: ParseUtils.asString(map['excerpt']),
      sourceTagUrl: _nullableString(map['sourceTagUrl']),
      badgeLabel: _nullableString(map['badgeLabel']),
      titleColorHex: _nullableString(map['titleColorHex']),
      isLocked: ParseUtils.asBool(map['isLocked']),
    );
  }

  Map<String, Object?> _encodeFilter(ForumDisplayFilterItem value) {
    return <String, Object?>{
      'label': value.label,
      'url': value.url,
      'isSelected': value.isSelected,
      'typeid': value.typeid,
    };
  }

  ForumDisplayFilterItem _decodeFilter(Map<String, dynamic> map) {
    return ForumDisplayFilterItem(
      label: ParseUtils.asString(map['label']),
      url: ParseUtils.asString(map['url']),
      isSelected: ParseUtils.asBool(map['isSelected']),
      typeid: ParseUtils.asString(map['typeid']),
    );
  }

  Map<String, Object?> _encodeSubForum(ForumDisplaySubForum value) {
    return <String, Object?>{
      'fid': value.fid,
      'title': value.title,
      'url': value.url,
      'iconUrl': value.iconUrl,
    };
  }

  ForumDisplaySubForum _decodeSubForum(Map<String, dynamic> map) {
    return ForumDisplaySubForum(
      fid: ParseUtils.asString(map['fid']),
      title: ParseUtils.asString(map['title']),
      url: ParseUtils.asString(map['url']),
      iconUrl: _nullableString(map['iconUrl']),
    );
  }

  Map<String, Object?> _encodeTopEntry(ForumDisplayTopEntry value) {
    return <String, Object?>{
      'title': value.title,
      'url': value.url,
      'tid': value.tid,
      'badgeLabel': value.badgeLabel,
      'titleColorHex': value.titleColorHex,
      'isAnnouncement': value.isAnnouncement,
    };
  }

  ForumDisplayTopEntry _decodeTopEntry(Map<String, dynamic> map) {
    return ForumDisplayTopEntry(
      title: ParseUtils.asString(map['title']),
      url: ParseUtils.asString(map['url']),
      tid: ParseUtils.asString(map['tid']),
      badgeLabel: ParseUtils.asString(map['badgeLabel']),
      titleColorHex: _nullableString(map['titleColorHex']),
      isAnnouncement: ParseUtils.asBool(map['isAnnouncement']),
    );
  }

  String? _nullableString(Object? value) {
    final text = ParseUtils.asString(value).trim();
    return text.isEmpty ? null : text;
  }

  int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }

  bool? _nullableBool(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return null;
  }
}
