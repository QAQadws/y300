import 'package:y300/features/forum/presentation/forum_content_projection_support.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

final class ForumHomeContentProjection {
  const ForumHomeContentProjection({
    required this.source,
    required this.sections,
    required this.mode,
    required this.sourceRevision,
    required this.isConverted,
  });

  factory ForumHomeContentProjection.raw(
    ForumHomeViewData source, {
    required TextConversionMode mode,
  }) {
    return ForumHomeContentProjection(
      source: source,
      sections: List<ForumHomeSectionProjection>.unmodifiable([
        for (final section in source.sections)
          ForumHomeSectionProjection.raw(section),
      ]),
      mode: mode,
      sourceRevision: sourceRevisionFor(source),
      isConverted: false,
    );
  }

  final ForumHomeViewData source;
  final List<ForumHomeSectionProjection> sections;
  final TextConversionMode mode;
  final String sourceRevision;
  final bool isConverted;

  static String sourceRevisionFor(ForumHomeViewData source) {
    final parts = <Object?>[source.isLoggedIn, source.carouselItems.length];
    for (final section in source.sections) {
      parts
        ..add(section.sourceIdentity)
        ..add(section.type.name)
        ..add(forumContentTextHash(section.title));
      for (final item in section.items) {
        parts
          ..add(item.fid)
          ..add(forumContentTextHash(item.title))
          ..add(forumContentTextHash(item.description))
          ..add(item.todayPosts);
      }
    }
    return forumContentSourceRevision(parts);
  }
}

final class ForumHomeSectionProjection {
  const ForumHomeSectionProjection({
    required this.source,
    required this.displayTitle,
    required this.items,
  });

  factory ForumHomeSectionProjection.raw(ForumSection source) {
    return ForumHomeSectionProjection(
      source: source,
      displayTitle: source.type == ForumSectionType.regular
          ? source.title
          : null,
      items: List<ForumHomeForumProjection>.unmodifiable([
        for (final item in source.items) ForumHomeForumProjection.raw(item),
      ]),
    );
  }

  final ForumSection source;
  final String? displayTitle;
  final List<ForumHomeForumProjection> items;
}

final class ForumHomeForumProjection {
  const ForumHomeForumProjection({
    required this.source,
    required this.displayTitle,
    required this.displayDescription,
  });

  factory ForumHomeForumProjection.raw(ForumHomeForumDisplayItem source) {
    return ForumHomeForumProjection(
      source: source,
      displayTitle: source.title,
      displayDescription: source.description,
    );
  }

  final ForumHomeForumDisplayItem source;
  final String displayTitle;
  final String displayDescription;
}
