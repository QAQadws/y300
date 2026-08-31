/// Models describing a forum display page and its server-provided actions.
library;

/// Values describing forum display favorite action.
enum ForumDisplayFavoriteAction {
  /// Favorite.
  favorite,

  /// Unfavorite.
  unfavorite,

  /// Unknown.
  unknown,
}

/// Query parameters for forum display.
class ForumDisplayQuery {
  /// Creates a [ForumDisplayQuery].
  const ForumDisplayQuery({
    required this.fid,
    this.page = 1,
    this.parameters = const <String, String>{},
  });

  /// Stable forum identifier.
  final String fid;

  /// Requested or current one-based page.
  final int page;

  /// Parameters.
  final Map<String, String> parameters;

  /// Source-neutral thread-type filter, if one is selected.
  String? get typeId {
    final value = parameters['typeid']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Whether the query requests last-post ordering.
  bool get ordersByLastPost =>
      parameters['orderby']?.trim().toLowerCase() == 'lastpost';

  /// Whether unclassified source parameters remain.
  bool get hasOpaqueParameters => parameters.keys.any(
    (key) =>
        key != 'fid' &&
        key != 'page' &&
        key != 'filter' &&
        key != 'typeid' &&
        key != 'orderby',
  );

  /// Creates a [ForumDisplayQuery].
  factory ForumDisplayQuery.initial({required String fid}) {
    return ForumDisplayQuery(fid: fid);
  }

  /// Creates a [ForumDisplayQuery].
  factory ForumDisplayQuery.fromUrl(
    String url, {
    required String fallbackFid,
    int fallbackPage = 1,
  }) {
    final uri = Uri.tryParse(url);
    final params = uri?.queryParameters ?? const <String, String>{};
    final fid = _nonEmpty(params['fid']) ?? fallbackFid;
    final page = _positiveInt(params['page']) ?? fallbackPage;
    return ForumDisplayQuery(
      fid: fid,
      page: page,
      parameters: _normalizedParameters(params),
    );
  }

  /// Returns a copy targeting [page].
  ForumDisplayQuery copyWithPage(int nextPage) {
    final normalized = nextPage < 1 ? 1 : nextPage;
    return ForumDisplayQuery(
      fid: fid,
      page: normalized,
      parameters: <String, String>{
        ...parameters,
        if (normalized > 1) 'page': normalized.toString() else 'page': '',
      },
    );
  }

  /// Converts this value to request parameters.
  Map<String, String> toRequestParameters() {
    final output = <String, String>{
      ...parameters,
      'mod': 'forumdisplay',
      'fid': fid,
      'mobile': '2',
    };
    if (page > 1) {
      output['page'] = page.toString();
    } else {
      output.remove('page');
    }
    output.removeWhere((key, value) => value.trim().isEmpty);
    return output;
  }

  static Map<String, String> _normalizedParameters(Map<String, String> source) {
    final output = <String, String>{};
    for (final entry in source.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      if (key == 'mod' || key == 'mobile') {
        continue;
      }
      output[key] = value;
    }
    return Map<String, String>.unmodifiable(output);
  }

  static String? _nonEmpty(String? source) {
    final value = source?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static int? _positiveInt(String? source) {
    final parsed = int.tryParse(source?.trim() ?? '');
    if (parsed == null || parsed < 1) {
      return null;
    }
    return parsed;
  }
}

/// 帖子摘要信息，用于 forumdisplay 列表渲染。
class ForumThreadSummary {
  /// Creates a [ForumThreadSummary].
  ForumThreadSummary({
    required this.tid,
    this.typeid = '',
    this.sourceTagName,
    required this.subject,
    required this.author,
    required this.replies,
    required this.views,
    required this.dateline,
    this.uid = '',
    this.avatarUrl,
    this.authorUrl,
    this.threadUrl,
    this.excerpt = '',
    this.sourceTagUrl,
    this.badgeLabel,
    this.titleColorHex,
    this.isLocked = false,
  });

  /// Stable thread identifier.
  final String tid;

  /// Stable Discuz thread-type identifier, or an empty string when absent.
  final String typeid;

  /// Source tag name.
  final String? sourceTagName;

  /// Subject.
  final String subject;

  /// Author.
  final String author;

  /// Replies.
  final int replies;

  /// Views.
  final int views;

  /// Dateline.
  final String dateline;

  /// Stable user identifier.
  final String uid;

  /// Avatar url.
  final String? avatarUrl;

  /// Author url.
  final String? authorUrl;

  /// Thread url.
  final String? threadUrl;

  /// Excerpt.
  final String excerpt;

  /// Source tag url.
  final String? sourceTagUrl;

  /// Badge label.
  final String? badgeLabel;

  /// Title color hex.
  final String? titleColorHex;

  /// Is locked.
  final bool isLocked;

  /// Returns a copy with the supplied changes.
  ForumThreadSummary copyWith({
    String? tid,
    String? typeid,
    String? sourceTagName,
    String? subject,
    String? author,
    int? replies,
    int? views,
    String? dateline,
    String? uid,
    String? avatarUrl,
    String? authorUrl,
    String? threadUrl,
    String? excerpt,
    String? sourceTagUrl,
    String? badgeLabel,
    String? titleColorHex,
    bool? isLocked,
    bool clearSourceTagName = false,
  }) {
    return ForumThreadSummary(
      tid: tid ?? this.tid,
      typeid: typeid ?? this.typeid,
      sourceTagName: clearSourceTagName
          ? null
          : (sourceTagName ?? this.sourceTagName),
      subject: subject ?? this.subject,
      author: author ?? this.author,
      replies: replies ?? this.replies,
      views: views ?? this.views,
      dateline: dateline ?? this.dateline,
      uid: uid ?? this.uid,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      authorUrl: authorUrl ?? this.authorUrl,
      threadUrl: threadUrl ?? this.threadUrl,
      excerpt: excerpt ?? this.excerpt,
      sourceTagUrl: sourceTagUrl ?? this.sourceTagUrl,
      badgeLabel: badgeLabel ?? this.badgeLabel,
      titleColorHex: titleColorHex ?? this.titleColorHex,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}

/// Source-neutral forum display filter item.
class ForumDisplayFilterItem {
  /// Creates a [ForumDisplayFilterItem].
  const ForumDisplayFilterItem({
    required this.label,
    required this.url,
    this.isSelected = false,
    this.typeid = '',
  });

  /// Label.
  final String label;

  /// Source-provided URL after validation.
  final String url;

  /// Is selected.
  final bool isSelected;

  /// Stable Discuz thread-type identifier represented by this filter.
  final String typeid;
}

/// Source-neutral forum display top entry.
class ForumDisplayTopEntry {
  /// Creates a [ForumDisplayTopEntry].
  const ForumDisplayTopEntry({
    required this.title,
    required this.url,
    this.tid = '',
    this.badgeLabel = '',
    this.titleColorHex,
    this.isAnnouncement = false,
  });

  /// Title.
  final String title;

  /// Source-provided URL after validation.
  final String url;

  /// Stable thread identifier.
  final String tid;

  /// Badge label.
  final String badgeLabel;

  /// Title color hex.
  final String? titleColorHex;

  /// Is announcement.
  final bool isAnnouncement;
}

/// Source-neutral forum display sub forum.
class ForumDisplaySubForum {
  /// Creates a [ForumDisplaySubForum].
  const ForumDisplaySubForum({
    required this.fid,
    required this.title,
    required this.url,
    this.iconUrl,
  });

  /// Stable forum identifier.
  final String fid;

  /// Title.
  final String title;

  /// Source-provided URL after validation.
  final String url;

  /// Icon url.
  final String? iconUrl;
}

/// Source-neutral forum display data.
class ForumDisplayData {
  /// Creates a [ForumDisplayData].
  ForumDisplayData({
    required this.fid,
    required this.forumName,
    required this.currentPage,
    required this.perPage,
    required this.totalThreads,
    required this.threads,
    this.headImageUrl,
    this.forumIconUrl,
    this.todayPosts = 0,
    this.rank = 0,
    this.primaryFilters = const <ForumDisplayFilterItem>[],
    this.typeFilters = const <ForumDisplayFilterItem>[],
    this.subForums = const <ForumDisplaySubForum>[],
    this.topEntries = const <ForumDisplayTopEntry>[],
    this.postUrl,
    this.searchUrl,
    this.favoriteUrl,
    this.favoriteAction = ForumDisplayFavoriteAction.unknown,
    this.previousPageUrl,
    this.nextPageUrl,
    this.lastPage,
    this.hasMoreOverride,
  });

  /// Stable forum identifier.
  final String fid;

  /// Forum name.
  final String forumName;

  /// Current one-based server page.
  final int currentPage;

  /// Per page.
  final int perPage;

  /// Total threads.
  final int totalThreads;

  /// Threads.
  final List<ForumThreadSummary> threads;

  /// Head image url.
  final String? headImageUrl;

  /// Forum icon url.
  final String? forumIconUrl;

  /// Today posts.
  final int todayPosts;

  /// Rank.
  final int rank;

  /// Primary filters.
  final List<ForumDisplayFilterItem> primaryFilters;

  /// Type filters.
  final List<ForumDisplayFilterItem> typeFilters;

  /// Sub forums.
  final List<ForumDisplaySubForum> subForums;

  /// Top entries.
  final List<ForumDisplayTopEntry> topEntries;

  /// Post url.
  final String? postUrl;

  /// Search url.
  final String? searchUrl;

  /// Favorite url.
  final String? favoriteUrl;

  /// Favorite action.
  final ForumDisplayFavoriteAction favoriteAction;

  /// Previous page url.
  final String? previousPageUrl;

  /// Next page url.
  final String? nextPageUrl;

  /// Last page.
  final int? lastPage;

  /// Has more override.
  final bool? hasMoreOverride;

  /// 当总数不可用时，退化为“本页数量达到 perPage”作为继续翻页依据
  bool get hasMore {
    final explicit = hasMoreOverride;
    if (explicit != null) {
      return explicit;
    }
    final parsedLastPage = lastPage;
    if (parsedLastPage != null && parsedLastPage > 0) {
      return currentPage < parsedLastPage;
    }
    if (totalThreads <= 0) {
      return threads.length >= perPage;
    }
    final loaded = currentPage * perPage;
    return loaded < totalThreads;
  }
}
