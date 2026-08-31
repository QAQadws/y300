// ignore_for_file: public_member_api_docs

import '../cache/forum_cache.dart';
import '../cache/forum_cache_key_canonicalizer.dart';
import '../contracts/forum_directory.dart';

/// Read-compatible projection of Y300's forum-home snapshots.
///
/// This codec is intentionally not used for writes: the application snapshot
/// also owns chrome and favorite projections that a directory adapter cannot
/// safely replace.
final class ForumDirectorySnapshotCodec
    implements ForumSnapshotCodec<ForumDirectoryData> {
  const ForumDirectorySnapshotCodec();

  @override
  String get snapshotType => ForumCacheKeyCanonicalizer.forumHomeSnapshotType;
  @override
  int get codecVersion => 4;
  @override
  int get parserVersion => 4;

  @override
  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) =>
      codecVersion == parserVersion &&
      (codecVersion == 2 || codecVersion == 3 || codecVersion == 4);

  @override
  Object? encode(ForumDirectoryData value) => <String, Object?>{
    'directory': _encodeDirectory(value),
  };

  @override
  ForumDirectoryData decode(Object? json) {
    final root = _map(json);
    if (root.containsKey('directory')) {
      return _decodeDirectory(root['directory']);
    }
    return _decodeLegacy(root);
  }

  Map<String, Object?> _encodeDirectory(ForumDirectoryData value) => {
    'sections': value.sections
        .map(
          (section) => <String, Object?>{
            'identity': section.identity,
            'title': section.title,
            'kind': section.kind.name,
            'forums': section.forums.map(_encodeForum).toList(growable: false),
          },
        )
        .toList(growable: false),
  };

  Map<String, Object?> _encodeForum(ForumDirectoryForum value) => {
    'fid': value.fid,
    'title': value.title,
    'description': value.description,
    'todayPosts': value.todayPosts,
    'children': value.children.map(_encodeForum).toList(growable: false),
  };

  ForumDirectoryData _decodeDirectory(Object? value) {
    final root = _map(value);
    return ForumDirectoryData(
      sections: _list(root['sections'])
          .map(_map)
          .map(
            (section) => ForumDirectorySection(
              identity: _text(section['identity']),
              title: _text(section['title']),
              kind: ForumDirectorySectionKind.values.firstWhere(
                (kind) => kind.name == _text(section['kind']),
                orElse: () => ForumDirectorySectionKind.regular,
              ),
              forums: _list(
                section['forums'],
              ).map(_map).map(_decodeForum).toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
  }

  ForumDirectoryForum _decodeForum(Map<String, Object?> value) =>
      ForumDirectoryForum(
        fid: _text(value['fid']),
        title: _text(value['title']),
        description: _text(value['description']),
        todayPosts: _integer(value['todayPosts']),
        children: _list(
          value['children'],
        ).map(_map).map(_decodeForum).toList(growable: false),
      );

  ForumDirectoryData _decodeLegacy(Map<String, Object?> root) {
    final homeSections = _list(root['homeSections'])
        .map(_map)
        .where((section) => _text(section['kind']) != 'favorite')
        .toList(growable: false);
    if (homeSections.isNotEmpty) {
      return ForumDirectoryData(
        sections: [
          for (var index = 0; index < homeSections.length; index++)
            ForumDirectorySection(
              identity: 'legacy-section-${index + 1}',
              title: _text(homeSections[index]['title']),
              forums: _list(homeSections[index]['items'])
                  .map(_map)
                  .map(
                    (forum) => ForumDirectoryForum(
                      fid: _text(forum['fid']),
                      title: _text(forum['title']),
                      description: _text(forum['description']),
                      todayPosts: _integer(forum['todayPosts']),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      );
    }
    final index = _map(root['forumIndex']);
    final forums = _list(index['forums'])
        .map(_map)
        .map(
          (forum) => ForumDirectoryForum(
            fid: _text(forum['fid']),
            title: _text(forum['name']),
            description: _text(forum['description']),
            todayPosts: _integer(forum['todayPosts']),
          ),
        )
        .toList(growable: false);
    final byId = {for (final forum in forums) forum.fid: forum};
    final assigned = <String>{};
    final sections = <ForumDirectorySection>[];
    for (final rawCategory in _list(index['categories'])) {
      final category = _map(rawCategory);
      final items = <ForumDirectoryForum>[];
      for (final rawId in _list(category['forums'])) {
        final id = _text(rawId);
        final forum = byId[id];
        if (forum != null) {
          assigned.add(id);
          items.add(forum);
        }
      }
      if (items.isNotEmpty) {
        sections.add(
          ForumDirectorySection(
            identity: _text(category['fid']),
            title: _text(category['name']),
            forums: items,
          ),
        );
      }
    }
    final rest = forums
        .where((forum) => !assigned.contains(forum.fid))
        .toList();
    if (rest.isNotEmpty) {
      sections.add(
        ForumDirectorySection(
          identity: 'legacy-uncategorized',
          title: '',
          forums: rest,
          kind: ForumDirectorySectionKind.uncategorized,
        ),
      );
    }
    return ForumDirectoryData(sections: sections);
  }

  Map<String, Object?> _map(Object? value) {
    if (value is! Map) return const <String, Object?>{};
    return {for (final entry in value.entries) '${entry.key}': entry.value};
  }

  List<Object?> _list(Object? value) =>
      value is List ? List<Object?>.from(value) : const <Object?>[];
  String _text(Object? value) => value?.toString().trim() ?? '';
  int? _integer(Object? value) =>
      value is int ? value : int.tryParse(value?.toString().trim() ?? '');
}
