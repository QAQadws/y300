import 'package:y300/core/utils/parse_utils.dart';

/// forumdisplay 字段映射工具，集中处理接口字段兼容，避免散落在业务模型中。
class ForumDisplayJsonMapper {
  const ForumDisplayJsonMapper._();

  static const List<String> _threadListKeys = <String>[
    'forum_threadlist',
    'threadlist',
  ];

  static const List<String> _perPageKeys = <String>[
    'perpage',
    'tpp',
  ];

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
  });

  final String tid;
  final String typeid;
  final String? sourceTagName;
  final String subject;
  final String author;
  final int replies;
  final int views;
  final String dateline;

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
    );
  }
}

class ForumDisplayData {
  ForumDisplayData({
    required this.fid,
    required this.forumName,
    required this.currentPage,
    required this.perPage,
    required this.totalThreads,
    required this.threads,
  });

  final String fid;
  final String forumName;
  final int currentPage;
  final int perPage;
  final int totalThreads;
  final List<ForumThreadSummary> threads;

  /// 当总数不可用时，退化为“本页数量达到 perPage”作为继续翻页依据
  bool get hasMore {
    if (totalThreads <= 0) {
      return threads.length >= perPage;
    }
    final loaded = currentPage * perPage;
    return loaded < totalThreads;
  }

  factory ForumDisplayData.fromVariables(JsonMap variables, {required int page}) {
    final forum = ParseUtils.asMap(variables['forum']);
    final perPage = ForumDisplayJsonMapper.parsePerPage(variables, fallback: 20);
    final totalThreads = ParseUtils.asInt(forum['threads']);

    return ForumDisplayData(
      fid: ParseUtils.asString(variables['fid'], fallback: ParseUtils.asString(forum['fid'])),
      forumName: ParseUtils.asString(forum['name']),
      currentPage: ForumDisplayJsonMapper.parseCurrentPage(variables, fallback: page),
      perPage: perPage,
      totalThreads: totalThreads,
      threads: ForumDisplayJsonMapper.parseThreadList(variables),
    );
  }
}
