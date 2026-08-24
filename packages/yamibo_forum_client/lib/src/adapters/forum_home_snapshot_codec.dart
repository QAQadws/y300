import '../contracts/forum_directory.dart';
import '../contracts/forum_home.dart';
import '../cache/forum_cache.dart';
import '../parsing/loose_json.dart';

final class ForumHomeSnapshotCodec
    implements ForumSnapshotCodec<ForumHomeDocument> {
  const ForumHomeSnapshotCodec();

  @override
  String get snapshotType => 'forum.home';
  @override
  int get codecVersion => 4;
  @override
  int get parserVersion => 4;

  @override
  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) => codecVersion == parserVersion && const {2, 3, 4}.contains(codecVersion);

  @override
  Object? encode(ForumHomeDocument value) => <String, Object?>{
    'directory': _directory(value.directory),
    'favoriteForums': value.favoriteForums.map(_favorite).toList(),
    'chromeData': <String, Object?>{
      'carouselItems': value.carousel
          .map(
            (item) => <String, Object?>{
              'imageUrl': item.imageUri.toString(),
              'targetUrl': item.targetUri.toString(),
            },
          )
          .toList(),
      'favoriteForums': value.favoriteForums.map(_favorite).toList(),
    },
  };

  @override
  ForumHomeDocument decode(Object? json) {
    final map = LooseJson.map(json);
    final directory = map.containsKey('directory')
        ? _decodeDirectory(map['directory'])
        : _decodeLegacyDirectory(map);
    final chrome = LooseJson.map(map['chromeData']);
    final favoritesSource = LooseJson.list(map['favoriteForums']).isNotEmpty
        ? LooseJson.list(map['favoriteForums'])
        : LooseJson.list(chrome['favoriteForums']);
    return ForumHomeDocument(
      directory: directory,
      carousel: LooseJson.list(chrome['carouselItems'])
          .map(LooseJson.map)
          .map((item) {
            final image = Uri.tryParse(LooseJson.string(item['imageUrl']));
            final target = Uri.tryParse(LooseJson.string(item['targetUrl']));
            return image == null || target == null
                ? null
                : ForumHomeCarouselReference(
                    imageUri: image,
                    targetUri: target,
                  );
          })
          .whereType<ForumHomeCarouselReference>()
          .toList(growable: false),
      favoriteForums: favoritesSource
          .map(LooseJson.map)
          .map(_decodeFavorite)
          .where((item) => item.fid.isNotEmpty)
          .toList(growable: false),
    );
  }

  Map<String, Object?> _directory(ForumDirectoryData value) => {
    'sections': value.sections
        .map(
          (section) => <String, Object?>{
            'identity': section.identity,
            'title': section.title,
            'kind': section.kind.name,
            'forums': section.forums.map(_forum).toList(),
          },
        )
        .toList(),
  };
  Map<String, Object?> _forum(ForumDirectoryForum value) => {
    'fid': value.fid,
    'title': value.title,
    'description': value.description,
    'todayPosts': value.todayPosts,
    'children': value.children.map(_forum).toList(),
  };
  Map<String, Object?> _favorite(ForumHomeFavoriteForum value) => {
    'fid': value.fid,
    'title': value.title,
    'description': value.description,
    'todayPosts': value.todayPosts,
  };

  ForumDirectoryData _decodeDirectory(Object? value) {
    final map = LooseJson.map(value);
    return ForumDirectoryData(
      sections: LooseJson.list(map['sections'])
          .map(LooseJson.map)
          .map(
            (section) => ForumDirectorySection(
              identity: LooseJson.string(section['identity']),
              title: LooseJson.string(section['title']),
              kind: ForumDirectorySectionKind.values.firstWhere(
                (kind) => kind.name == LooseJson.string(section['kind']),
                orElse: () => ForumDirectorySectionKind.regular,
              ),
              forums: LooseJson.list(
                section['forums'],
              ).map(LooseJson.map).map(_decodeForum).toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
  }

  ForumDirectoryForum _decodeForum(Map<String, Object?> map) =>
      ForumDirectoryForum(
        fid: LooseJson.string(map['fid']),
        title: LooseJson.string(map['title']),
        description: LooseJson.string(map['description']),
        todayPosts: map['todayPosts'] == null
            ? null
            : LooseJson.integer(map['todayPosts']),
        children: LooseJson.list(
          map['children'],
        ).map(LooseJson.map).map(_decodeForum).toList(growable: false),
      );

  ForumHomeFavoriteForum _decodeFavorite(Map<String, Object?> map) =>
      ForumHomeFavoriteForum(
        fid: LooseJson.string(map['fid']),
        title: LooseJson.string(map['title']),
        description: LooseJson.string(map['description']),
        todayPosts: map['todayPosts'] == null
            ? null
            : LooseJson.integer(map['todayPosts']),
      );

  ForumDirectoryData _decodeLegacyDirectory(Map<String, Object?> map) {
    final sections = LooseJson.list(map['homeSections'])
        .map(LooseJson.map)
        .where((section) => LooseJson.string(section['kind']) != 'favorite')
        .toList(growable: false);
    if (sections.isNotEmpty) {
      return ForumDirectoryData(
        sections: [
          for (var i = 0; i < sections.length; i++)
            ForumDirectorySection(
              identity: 'legacy-section-${i + 1}',
              title: LooseJson.string(sections[i]['title']),
              forums: LooseJson.list(sections[i]['items'])
                  .map(LooseJson.map)
                  .map(
                    (item) => ForumDirectoryForum(
                      fid: LooseJson.string(item['fid']),
                      title: LooseJson.string(item['title']),
                      description: LooseJson.string(item['description']),
                      todayPosts: item['todayPosts'] == null
                          ? null
                          : LooseJson.integer(item['todayPosts']),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      );
    }
    final index = LooseJson.map(map['forumIndex']);
    final forums = LooseJson.list(index['forums'])
        .map(LooseJson.map)
        .map(
          (item) => ForumDirectoryForum(
            fid: LooseJson.string(item['fid']),
            title: LooseJson.string(item['name']),
            description: LooseJson.string(item['description']),
            todayPosts: item['todayPosts'] == null
                ? null
                : LooseJson.integer(item['todayPosts']),
          ),
        )
        .toList(growable: false);
    return ForumDirectoryData(
      sections: forums.isEmpty
          ? const []
          : [
              ForumDirectorySection(
                identity: 'legacy-uncategorized',
                title: '',
                forums: forums,
                kind: ForumDirectorySectionKind.uncategorized,
              ),
            ],
    );
  }
}
