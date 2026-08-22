import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/forum/domain/models/forum_display_models.dart';

final class ForumDisplayApiMapper {
  const ForumDisplayApiMapper();

  static const List<String> _threadListKeys = <String>[
    'forum_threadlist',
    'threadlist',
  ];

  static const List<String> _perPageKeys = <String>['perpage', 'tpp'];

  ForumDisplayData mapVariables(JsonMap variables, {required int page}) {
    final forum = ParseUtils.asMap(variables['forum']);
    final perPage = _parsePerPage(variables, fallback: 20);
    return ForumDisplayData(
      fid: ParseUtils.asString(
        variables['fid'],
        fallback: ParseUtils.asString(forum['fid']),
      ),
      forumName: ParseUtils.asString(forum['name']),
      currentPage: _parseCurrentPage(variables, fallback: page),
      perPage: perPage,
      totalThreads: ParseUtils.asInt(forum['threads']),
      threads: _parseThreadList(variables),
      favoriteAction: ForumDisplayFavoriteAction.unknown,
    );
  }

  List<ForumThreadSummary> _parseThreadList(JsonMap variables) {
    final rawList = _pickFirstList(variables, _threadListKeys);
    return rawList
        .map((item) => _mapThread(ParseUtils.asMap(item)))
        .toList(growable: false);
  }

  ForumThreadSummary _mapThread(JsonMap json) {
    return ForumThreadSummary(
      tid: ParseUtils.asString(json['tid']),
      typeid: ParseUtils.asString(json['typeid']),
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

  int _parsePerPage(JsonMap variables, {required int fallback}) {
    for (final key in _perPageKeys) {
      final parsed = ParseUtils.asInt(variables[key], fallback: -1);
      if (parsed > 0) {
        return parsed;
      }
    }
    return fallback;
  }

  int _parseCurrentPage(JsonMap variables, {required int fallback}) {
    final parsed = ParseUtils.asInt(variables['page'], fallback: fallback);
    return parsed > 0 ? parsed : fallback;
  }

  List<dynamic> _pickFirstList(JsonMap source, List<String> keys) {
    for (final key in keys) {
      final list = ParseUtils.asList(source[key]);
      if (list.isNotEmpty) {
        return list;
      }
    }
    return const <dynamic>[];
  }

  String? _nullableString(dynamic value) {
    final text = ParseUtils.asString(value).trim();
    return text.isEmpty ? null : text;
  }
}
