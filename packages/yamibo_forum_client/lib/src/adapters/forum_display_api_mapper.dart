// ignore_for_file: public_member_api_docs

import '../contracts/forum_display_models.dart';
import '../parsing/loose_json.dart';

final class ForumDisplayApiMapper {
  const ForumDisplayApiMapper();

  static const List<String> _threadListKeys = <String>[
    'forum_threadlist',
    'threadlist',
  ];

  static const List<String> _perPageKeys = <String>['perpage', 'tpp'];

  ForumDisplayData mapVariables(JsonMap variables, {required int page}) {
    final forum = LooseJson.map(variables['forum']);
    final perPage = _parsePerPage(variables, fallback: 20);
    return ForumDisplayData(
      fid: LooseJson.string(
        variables['fid'],
        fallback: LooseJson.string(forum['fid']),
      ),
      forumName: LooseJson.string(forum['name']),
      currentPage: _parseCurrentPage(variables, fallback: page),
      perPage: perPage,
      totalThreads: LooseJson.integer(forum['threads']),
      threads: _parseThreadList(variables),
      favoriteAction: ForumDisplayFavoriteAction.unknown,
    );
  }

  List<ForumThreadSummary> _parseThreadList(JsonMap variables) {
    final rawList = _pickFirstList(variables, _threadListKeys);
    return rawList
        .map((item) => _mapThread(LooseJson.map(item)))
        .toList(growable: false);
  }

  ForumThreadSummary _mapThread(JsonMap json) {
    return ForumThreadSummary(
      tid: LooseJson.string(json['tid']),
      typeid: LooseJson.string(json['typeid']),
      subject: LooseJson.string(json['subject']),
      author: LooseJson.string(
        json['author'],
        fallback: LooseJson.string(json['authorname']),
      ),
      replies: LooseJson.integer(json['replies']),
      views: LooseJson.integer(json['views']),
      dateline: LooseJson.string(
        json['dateline'],
        fallback: LooseJson.string(json['dbdateline']),
      ),
      uid: LooseJson.string(
        json['authorid'],
        fallback: LooseJson.string(json['uid']),
      ),
      avatarUrl: _nullableString(json['avatar']),
      authorUrl: _nullableString(json['authorUrl']),
      threadUrl: _nullableString(json['threadUrl']),
      excerpt: LooseJson.string(
        json['message'],
        fallback: LooseJson.string(json['excerpt']),
      ),
      sourceTagUrl: _nullableString(json['sourceTagUrl']),
      badgeLabel: _nullableString(json['badgeLabel']),
      titleColorHex: _nullableString(json['titleColorHex']),
      isLocked: LooseJson.boolean(json['closed']),
    );
  }

  int _parsePerPage(JsonMap variables, {required int fallback}) {
    for (final key in _perPageKeys) {
      final parsed = LooseJson.integer(variables[key], fallback: -1);
      if (parsed > 0) {
        return parsed;
      }
    }
    return fallback;
  }

  int _parseCurrentPage(JsonMap variables, {required int fallback}) {
    final parsed = LooseJson.integer(variables['page'], fallback: fallback);
    return parsed > 0 ? parsed : fallback;
  }

  List<dynamic> _pickFirstList(JsonMap source, List<String> keys) {
    for (final key in keys) {
      final list = LooseJson.list(source[key]);
      if (list.isNotEmpty) {
        return list;
      }
    }
    return const <dynamic>[];
  }

  String? _nullableString(dynamic value) {
    final text = LooseJson.string(value).trim();
    return text.isEmpty ? null : text;
  }
}
