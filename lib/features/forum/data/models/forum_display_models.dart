import 'package:y300/core/utils/parse_utils.dart';

enum ForumDisplayFavoriteAction { favorite, unfavorite, unknown }

class ForumDisplayQuery {
  const ForumDisplayQuery({
    required this.fid,
    this.page = 1,
    this.parameters = const <String, String>{},
  });

  final String fid;
  final int page;
  final Map<String, String> parameters;

  factory ForumDisplayQuery.initial({required String fid}) {
    return ForumDisplayQuery(fid: fid);
  }

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

/// forumdisplay 字段映射工具，集中处理接口字段兼容，避免散落在业务模型中。
class ForumDisplayJsonMapper {
  const ForumDisplayJsonMapper._();

  static const List<String> _threadListKeys = <String>[
    'forum_threadlist',
    'threadlist',
  ];

  static const List<String> _perPageKeys = <String>['perpage', 'tpp'];

  static List<ForumThreadSummary> parseThreadList(JsonMap variables) {
    final rawList = _pickFirstList(variables, _threadListKeys);
    return rawList
        .map((item) => ForumThreadSummary.fromJson(ParseUtils.asMap(item)))
        .toList();
  }

  static int parsePerPage(JsonMap variables, {int fallback = 20}) {
    for (final key in _perPageKeys) {
      final parsed = ParseUtils.asInt(variables[key], fallback: -1);
      if (parsed > 0) {
        return parsed;
      }
    }
    return fallback;
  }

  static int parseCurrentPage(JsonMap variables, {required int fallback}) {
    final parsed = ParseUtils.asInt(variables['page'], fallback: fallback);
    return parsed > 0 ? parsed : fallback;
  }

  static List<dynamic> _pickFirstList(JsonMap source, List<String> keys) {
    for (final key in keys) {
      final list = ParseUtils.asList(source[key]);
      if (list.isNotEmpty) {
        return list;
      }
    }
    return const <dynamic>[];
  }
}

/// 帖子摘要信息，用于 forumdisplay 列表渲染。
class ForumThreadSummary {
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

  final String tid;
  final String typeid;
  final String? sourceTagName;
  final String subject;
  final String author;
  final int replies;
  final int views;
  final String dateline;
  final String uid;
  final String? avatarUrl;
  final String? authorUrl;
  final String? threadUrl;
  final String excerpt;
  final String? sourceTagUrl;
  final String? badgeLabel;
  final String? titleColorHex;
  final bool isLocked;

  factory ForumThreadSummary.fromJson(JsonMap json) {
    return ForumThreadSummary(
      tid: ParseUtils.asString(json['tid']),
      typeid: ParseUtils.asString(json['typeid']),
      sourceTagName: null,
      subject: ParseUtils.asString(json['subject']),
      author: ParseUtils.asString(
        json['author'],
        fallback: ParseUtils.asString(json['authorname']),
      ),
      replies: ParseUtils.asInt(json['replies']),
      views: ParseUtils.asInt(json['views']),
      dateline: ParseUtils.asString(
        json['dateline'],
        fallback: ParseUtils.asString(json['dbdateline']),
      ),
      uid: ParseUtils.asString(
        json['authorid'],
        fallback: ParseUtils.asString(json['uid']),
      ),
      avatarUrl: _nullableString(json['avatar']),
      authorUrl: _nullableString(json['authorUrl']),
      threadUrl: _nullableString(json['threadUrl']),
      excerpt: ParseUtils.asString(
        json['message'],
        fallback: ParseUtils.asString(json['excerpt']),
      ),
      sourceTagUrl: _nullableString(json['sourceTagUrl']),
      badgeLabel: _nullableString(json['badgeLabel']),
      titleColorHex: _nullableString(json['titleColorHex']),
      isLocked: ParseUtils.asBool(json['closed']),
    );
  }

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

  static String? _nullableString(dynamic value) {
    final text = ParseUtils.asString(value).trim();
    return text.isEmpty ? null : text;
  }
}

class ForumDisplayFilterItem {
  const ForumDisplayFilterItem({
    required this.label,
    required this.url,
    this.isSelected = false,
    this.typeid = '',
  });

  final String label;
  final String url;
  final bool isSelected;
  final String typeid;
}

class ForumDisplayTopEntry {
  const ForumDisplayTopEntry({
    required this.title,
    required this.url,
    this.tid = '',
    this.badgeLabel = '',
    this.titleColorHex,
    this.isAnnouncement = false,
  });

  final String title;
  final String url;
  final String tid;
  final String badgeLabel;
  final String? titleColorHex;
  final bool isAnnouncement;
}

class ForumDisplaySubForum {
  const ForumDisplaySubForum({
    required this.fid,
    required this.title,
    required this.url,
    this.iconUrl,
  });

  final String fid;
  final String title;
  final String url;
  final String? iconUrl;
}

class ForumDisplayData {
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

  final String fid;
  final String forumName;
  final int currentPage;
  final int perPage;
  final int totalThreads;
  final List<ForumThreadSummary> threads;
  final String? headImageUrl;
  final String? forumIconUrl;
  final int todayPosts;
  final int rank;
  final List<ForumDisplayFilterItem> primaryFilters;
  final List<ForumDisplayFilterItem> typeFilters;
  final List<ForumDisplaySubForum> subForums;
  final List<ForumDisplayTopEntry> topEntries;
  final String? postUrl;
  final String? searchUrl;
  final String? favoriteUrl;
  final ForumDisplayFavoriteAction favoriteAction;
  final String? previousPageUrl;
  final String? nextPageUrl;
  final int? lastPage;
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

  factory ForumDisplayData.fromVariables(
    JsonMap variables, {
    required int page,
  }) {
    final forum = ParseUtils.asMap(variables['forum']);
    final perPage = ForumDisplayJsonMapper.parsePerPage(
      variables,
      fallback: 20,
    );
    final totalThreads = ParseUtils.asInt(forum['threads']);

    return ForumDisplayData(
      fid: ParseUtils.asString(
        variables['fid'],
        fallback: ParseUtils.asString(forum['fid']),
      ),
      forumName: ParseUtils.asString(forum['name']),
      currentPage: ForumDisplayJsonMapper.parseCurrentPage(
        variables,
        fallback: page,
      ),
      perPage: perPage,
      totalThreads: totalThreads,
      threads: ForumDisplayJsonMapper.parseThreadList(variables),
      favoriteAction: ForumDisplayFavoriteAction.unknown,
    );
  }
}
