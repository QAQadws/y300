import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/domain/models/forum_directory_models.dart';

class ForumHomeSnapshotCodec
    implements
        SnapshotCodec<ForumHomePayload>,
        SnapshotCodecVersionCompatibility {
  const ForumHomeSnapshotCodec();

  @override
  String get snapshotType => CacheKeyCanonicalizer.forumHomeSnapshotType;

  @override
  int get codecVersion => 4;

  @override
  int get parserVersion => 4;

  @override
  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) {
    return codecVersion == 4 && parserVersion == 4 ||
        codecVersion == 3 && parserVersion == 3 ||
        codecVersion == 2 && parserVersion == 2;
  }

  @override
  Object? encode(ForumHomePayload value) {
    return <String, Object?>{
      'isLoggedIn': value.isLoggedIn,
      'directory': _encodeDirectory(value.directory),
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
      directory: map.containsKey('directory')
          ? _decodeDirectory(map['directory'])
          : _decodeLegacyDirectory(map),
      isLoggedIn: ParseUtils.asBool(map['isLoggedIn']),
      favoriteForums: ParseUtils.asList(map['favoriteForums'])
          .map((item) => _decodeFavoriteForum(ParseUtils.asMap(item)))
          .toList(growable: false),
      chromeData: _decodeChromeData(map['chromeData']),
    );
  }

  Map<String, Object?> _encodeDirectory(ForumDirectoryData value) {
    return <String, Object?>{
      'sections': value.sections
          .map(_encodeDirectorySection)
          .toList(growable: false),
    };
  }

  ForumDirectoryData _decodeDirectory(Object? value) {
    final map = ParseUtils.asMap(value);
    return ForumDirectoryData(
      sections: ParseUtils.asList(map['sections'])
          .map((item) => _decodeDirectorySection(ParseUtils.asMap(item)))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodeDirectorySection(ForumDirectorySection value) {
    return <String, Object?>{
      'identity': value.identity,
      'title': value.title,
      'kind': value.kind.name,
      'forums': value.forums.map(_encodeDirectoryForum).toList(growable: false),
    };
  }

  ForumDirectorySection _decodeDirectorySection(Map<String, dynamic> map) {
    return ForumDirectorySection(
      identity: ParseUtils.asString(map['identity']),
      title: ParseUtils.asString(map['title']),
      kind: ForumDirectorySectionKind.values.firstWhere(
        (kind) => kind.name == ParseUtils.asString(map['kind']),
        orElse: () => ForumDirectorySectionKind.regular,
      ),
      forums: ParseUtils.asList(map['forums'])
          .map((item) => _decodeDirectoryForum(ParseUtils.asMap(item)))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodeDirectoryForum(ForumDirectoryForum value) {
    return <String, Object?>{
      'fid': value.fid,
      'title': value.title,
      'description': value.description,
      'todayPosts': value.todayPosts,
      'children': value.children
          .map(_encodeDirectoryForum)
          .toList(growable: false),
    };
  }

  ForumDirectoryForum _decodeDirectoryForum(Map<String, dynamic> map) {
    return ForumDirectoryForum(
      fid: ParseUtils.asString(map['fid']),
      title: ParseUtils.asString(map['title']),
      description: ParseUtils.asString(map['description']),
      todayPosts: _nullableInt(map['todayPosts']),
      children: ParseUtils.asList(map['children'])
          .map((item) => _decodeDirectoryForum(ParseUtils.asMap(item)))
          .toList(growable: false),
    );
  }

  ForumDirectoryData _decodeLegacyForumIndex(Object? value) {
    final map = ParseUtils.asMap(value);
    final forums = ParseUtils.asList(map['forums'])
        .map((item) => _decodeLegacyForum(ParseUtils.asMap(item)))
        .toList(growable: false);
    final forumById = <String, ForumDirectoryForum>{
      for (final forum in forums) forum.fid: forum,
    };
    final sections = <ForumDirectorySection>[];
    final categorized = <String>{};
    for (final categoryValue in ParseUtils.asList(map['categories'])) {
      final category = ParseUtils.asMap(categoryValue);
      final forumItems = <ForumDirectoryForum>[];
      for (final rawFid in ParseUtils.asList(category['forums'])) {
        final forum = forumById[rawFid.toString()];
        if (forum != null) {
          categorized.add(forum.fid);
          forumItems.add(forum);
        }
      }
      if (forumItems.isNotEmpty) {
        sections.add(
          ForumDirectorySection(
            identity: ParseUtils.asString(category['fid']),
            title: ParseUtils.asString(category['name']),
            forums: forumItems,
          ),
        );
      }
    }
    final uncategorized = forums
        .where((forum) => !categorized.contains(forum.fid))
        .toList(growable: false);
    if (uncategorized.isNotEmpty) {
      sections.add(
        ForumDirectorySection(
          identity: 'legacy-uncategorized',
          title: '',
          forums: uncategorized,
          kind: ForumDirectorySectionKind.uncategorized,
        ),
      );
    }
    return ForumDirectoryData(sections: sections);
  }

  ForumDirectoryData _decodeLegacyDirectory(Map<String, dynamic> map) {
    final legacySections = ParseUtils.asList(map['homeSections']);
    final regularSections = legacySections
        .map(ParseUtils.asMap)
        .where((section) => ParseUtils.asString(section['kind']) != 'favorite')
        .toList(growable: false);
    if (regularSections.isEmpty) {
      return _decodeLegacyForumIndex(map['forumIndex']);
    }

    final index = ParseUtils.asMap(map['forumIndex']);
    final identityByTitle = <String, String>{
      for (final value in ParseUtils.asList(index['categories']))
        ParseUtils.asString(ParseUtils.asMap(value)['name']):
            ParseUtils.asString(ParseUtils.asMap(value)['fid']),
    };
    return ForumDirectoryData(
      sections: [
        for (var index = 0; index < regularSections.length; index++)
          ForumDirectorySection(
            identity:
                identityByTitle[ParseUtils.asString(
                  regularSections[index]['title'],
                )] ??
                'legacy-section-${index + 1}',
            title: ParseUtils.asString(regularSections[index]['title']),
            forums: ParseUtils.asList(regularSections[index]['items'])
                .map(ParseUtils.asMap)
                .map(
                  (forum) => ForumDirectoryForum(
                    fid: ParseUtils.asString(forum['fid']),
                    title: ParseUtils.asString(forum['title']),
                    description: ParseUtils.asString(forum['description']),
                    todayPosts: _nullableInt(forum['todayPosts']),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  ForumDirectoryForum _decodeLegacyForum(Map<String, dynamic> map) {
    return ForumDirectoryForum(
      fid: ParseUtils.asString(map['fid']),
      title: ParseUtils.asString(map['name']),
      description: ParseUtils.asString(map['description']),
      todayPosts: _nullableInt(map['todayPosts']),
      children: ParseUtils.asList(map['subForums'])
          .map((item) => _decodeLegacyForum(ParseUtils.asMap(item)))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodeFavoriteForum(ForumHomeFavoriteForum value) {
    return <String, Object?>{
      'fid': value.fid,
      'title': value.title,
      'description': value.description,
      'todayPosts': value.todayPosts,
    };
  }

  ForumHomeFavoriteForum _decodeFavoriteForum(Map<String, dynamic> map) {
    return ForumHomeFavoriteForum(
      fid: ParseUtils.asString(map['fid']),
      title: ParseUtils.asString(map['title']),
      description: ParseUtils.asString(map['description']),
      todayPosts: _nullableInt(map['todayPosts']),
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
      todayPosts: _nullableInt(map['todayPosts']),
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

  int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }
}
