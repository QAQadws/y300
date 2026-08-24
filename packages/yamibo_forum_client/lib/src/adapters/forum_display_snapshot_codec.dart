import '../cache/forum_cache.dart';
import '../cache/forum_cache_key_canonicalizer.dart';
import '../contracts/forum_display_models.dart';
import '../parsing/loose_json.dart';

class ForumDisplaySnapshotCodec
    implements ForumSnapshotCodec<ForumDisplayData> {
  const ForumDisplaySnapshotCodec();

  @override
  String get snapshotType =>
      ForumCacheKeyCanonicalizer.forumDisplaySnapshotType;

  @override
  int get codecVersion => 1;

  @override
  int get parserVersion => 1;

  @override
  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) =>
      codecVersion == this.codecVersion && parserVersion == this.parserVersion;

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
      'favoriteAction': value.favoriteAction.name,
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
    final map = LooseJson.map(json);
    return ForumDisplayData(
      fid: LooseJson.string(map['fid']),
      forumName: LooseJson.string(map['forumName']),
      currentPage: LooseJson.integer(map['currentPage'], fallback: 1),
      perPage: LooseJson.integer(map['perPage'], fallback: 20),
      totalThreads: LooseJson.integer(map['totalThreads']),
      headImageUrl: _nullableString(map['headImageUrl']),
      forumIconUrl: _nullableString(map['forumIconUrl']),
      todayPosts: LooseJson.integer(map['todayPosts']),
      rank: LooseJson.integer(map['rank']),
      postUrl: _nullableString(map['postUrl']),
      searchUrl: _nullableString(map['searchUrl']),
      favoriteUrl: _nullableString(map['favoriteUrl']),
      favoriteAction: _decodeFavoriteAction(map),
      previousPageUrl: _nullableString(map['previousPageUrl']),
      nextPageUrl: _nullableString(map['nextPageUrl']),
      lastPage: _nullableInt(map['lastPage']),
      hasMoreOverride: _nullableBool(map['hasMoreOverride']),
      threads: LooseJson.list(map['threads'])
          .map((item) => _decodeThread(LooseJson.map(item)))
          .toList(growable: false),
      primaryFilters: LooseJson.list(map['primaryFilters'])
          .map((item) => _decodeFilter(LooseJson.map(item)))
          .toList(growable: false),
      typeFilters: LooseJson.list(map['typeFilters'])
          .map((item) => _decodeFilter(LooseJson.map(item)))
          .toList(growable: false),
      subForums: LooseJson.list(map['subForums'])
          .map((item) => _decodeSubForum(LooseJson.map(item)))
          .toList(growable: false),
      topEntries: LooseJson.list(map['topEntries'])
          .map((item) => _decodeTopEntry(LooseJson.map(item)))
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
      tid: LooseJson.string(map['tid']),
      typeid: LooseJson.string(map['typeid']),
      sourceTagName: _nullableString(map['sourceTagName']),
      subject: LooseJson.string(map['subject']),
      author: LooseJson.string(map['author']),
      replies: LooseJson.integer(map['replies']),
      views: LooseJson.integer(map['views']),
      dateline: LooseJson.string(map['dateline']),
      uid: LooseJson.string(map['uid']),
      avatarUrl: _nullableString(map['avatarUrl']),
      authorUrl: _nullableString(map['authorUrl']),
      threadUrl: _nullableString(map['threadUrl']),
      excerpt: LooseJson.string(map['excerpt']),
      sourceTagUrl: _nullableString(map['sourceTagUrl']),
      badgeLabel: _nullableString(map['badgeLabel']),
      titleColorHex: _nullableString(map['titleColorHex']),
      isLocked: LooseJson.boolean(map['isLocked']),
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
      label: LooseJson.string(map['label']),
      url: LooseJson.string(map['url']),
      isSelected: LooseJson.boolean(map['isSelected']),
      typeid: LooseJson.string(map['typeid']),
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
      fid: LooseJson.string(map['fid']),
      title: LooseJson.string(map['title']),
      url: LooseJson.string(map['url']),
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
      title: LooseJson.string(map['title']),
      url: LooseJson.string(map['url']),
      tid: LooseJson.string(map['tid']),
      badgeLabel: LooseJson.string(map['badgeLabel']),
      titleColorHex: _nullableString(map['titleColorHex']),
      isAnnouncement: LooseJson.boolean(map['isAnnouncement']),
    );
  }

  String? _nullableString(Object? value) {
    final text = LooseJson.string(value).trim();
    return text.isEmpty ? null : text;
  }

  ForumDisplayFavoriteAction _decodeFavoriteAction(Map<String, dynamic> map) {
    final raw = LooseJson.string(map['favoriteAction']).trim();
    switch (raw) {
      case 'favorite':
        return ForumDisplayFavoriteAction.favorite;
      case 'unfavorite':
        return ForumDisplayFavoriteAction.unfavorite;
      case 'unknown':
        return ForumDisplayFavoriteAction.unknown;
      default:
        // Older snapshots only stored favoriteUrl. It represented the
        // positive action; never infer an unfavorite action from old data.
        return _nullableString(map['favoriteUrl']) == null
            ? ForumDisplayFavoriteAction.unknown
            : ForumDisplayFavoriteAction.favorite;
    }
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
