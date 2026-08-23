import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/forum/domain/models/forum_directory_models.dart';

final class ForumDirectoryApiMapper {
  const ForumDirectoryApiMapper();

  ForumDirectoryData mapVariables(JsonMap variables) {
    final rawCategories = variables['catlist'];
    final rawForums = variables['forumlist'];
    if (rawCategories is! List || rawForums is! List) {
      throw const FormatException(
        'forumindex response is missing catlist or forumlist',
      );
    }

    final forums = <ForumDirectoryForum>[];
    final forumIds = <String>{};
    for (final item in rawForums) {
      final forum = _mapForum(ParseUtils.asMap(item));
      if (!forumIds.add(forum.fid)) {
        throw const FormatException('forumindex contains duplicate forum fid');
      }
      forums.add(forum);
    }
    final forumById = <String, ForumDirectoryForum>{
      for (final forum in forums) forum.fid: forum,
    };
    final sections = <ForumDirectorySection>[];
    final categorized = <String>{};
    for (final item in rawCategories) {
      final category = ParseUtils.asMap(item);
      final identity = ParseUtils.asString(category['fid']).trim();
      final title = ParseUtils.asString(category['name']).trim();
      if (identity.isEmpty || title.isEmpty) {
        throw const FormatException('forumindex category identity is invalid');
      }
      final rawFids = category['forums'];
      if (rawFids is! List) {
        throw const FormatException('forumindex category forums is invalid');
      }
      final categoryForums = <ForumDirectoryForum>[];
      for (final rawFid in rawFids) {
        final fid = rawFid.toString().trim();
        final forum = forumById[fid];
        if (forum == null) {
          throw FormatException('forumindex references unknown forum $fid');
        }
        categorized.add(fid);
        categoryForums.add(forum);
      }
      sections.add(
        ForumDirectorySection(
          identity: identity,
          title: title,
          forums: categoryForums,
        ),
      );
    }

    final uncategorized = forums
        .where((forum) => !categorized.contains(forum.fid))
        .toList(growable: false);
    if (uncategorized.isNotEmpty) {
      sections.add(
        ForumDirectorySection(
          identity: 'api-uncategorized',
          title: '',
          forums: uncategorized,
          kind: ForumDirectorySectionKind.uncategorized,
        ),
      );
    }
    return ForumDirectoryData(sections: sections);
  }

  ForumDirectoryForum _mapForum(JsonMap json) {
    final fid = ParseUtils.asString(json['fid']).trim();
    final title = ParseUtils.asString(json['name']).trim();
    if (fid.isEmpty || title.isEmpty) {
      throw const FormatException('forumindex forum identity is invalid');
    }
    final rawChildren = json['sublist'];
    if (rawChildren != null && rawChildren is! List) {
      throw const FormatException('forumindex sublist is invalid');
    }
    return ForumDirectoryForum(
      fid: fid,
      title: title,
      description: ParseUtils.asString(json['description']),
      todayPosts: _nullableInt(json['todayposts']),
      children: [
        for (final item in (rawChildren as List? ?? const <dynamic>[]))
          _mapForum(ParseUtils.asMap(item)),
      ],
    );
  }

  int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw const FormatException('forumindex todayposts is invalid');
    }
    return parsed;
  }
}
