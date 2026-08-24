import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/forum/presentation/forum_content_projection_support.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

final class ForumDisplayContentProjection {
  const ForumDisplayContentProjection({
    required this.sourceState,
    required this.displayTitle,
    required this.primaryFilters,
    required this.typeFilters,
    required this.subForums,
    required this.topEntries,
    required this.threads,
    required this.mode,
    required this.sourceRevision,
    required this.isConverted,
  });

  factory ForumDisplayContentProjection.raw(
    ForumDisplayPageState source, {
    required TextConversionMode mode,
  }) {
    return ForumDisplayContentProjection(
      sourceState: source,
      displayTitle: source.title,
      primaryFilters: List<ForumDisplayFilterProjection>.unmodifiable([
        for (final item in source.primaryFilters)
          ForumDisplayFilterProjection.raw(item),
      ]),
      typeFilters: List<ForumDisplayFilterProjection>.unmodifiable([
        for (final item in source.typeFilters)
          ForumDisplayFilterProjection.raw(item),
      ]),
      subForums: List<ForumDisplaySubForumProjection>.unmodifiable([
        for (final item in source.subForums)
          ForumDisplaySubForumProjection.raw(item),
      ]),
      topEntries: List<ForumDisplayTopEntryProjection>.unmodifiable([
        for (final item in source.topEntries)
          ForumDisplayTopEntryProjection.raw(item),
      ]),
      threads: List<ForumDisplayThreadProjection>.unmodifiable([
        for (final item in source.threads)
          ForumDisplayThreadProjection.raw(item),
      ]),
      mode: mode,
      sourceRevision: sourceRevisionFor(source),
      isConverted: false,
    );
  }

  final ForumDisplayPageState sourceState;
  final String displayTitle;
  final List<ForumDisplayFilterProjection> primaryFilters;
  final List<ForumDisplayFilterProjection> typeFilters;
  final List<ForumDisplaySubForumProjection> subForums;
  final List<ForumDisplayTopEntryProjection> topEntries;
  final List<ForumDisplayThreadProjection> threads;
  final TextConversionMode mode;
  final String sourceRevision;
  final bool isConverted;

  static String sourceRevisionFor(ForumDisplayPageState source) {
    final parts = <Object?>[
      source.fid,
      source.currentPage,
      source.query.parameters.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('&'),
      forumContentTextHash(source.title),
      source.headImageUrl,
      source.headImageDimensions?.width,
      source.headImageDimensions?.height,
      source.threads.length,
      source.capabilities?.paginationPrecision,
      source.readMetadata?.origin,
      source.readMetadata?.freshness,
    ];
    final capabilityEntries =
        source.capabilities?.values.values.entries.toList()
          ?..sort((left, right) => left.key.index.compareTo(right.key.index));
    for (final entry in capabilityEntries ?? const []) {
      parts
        ..add(entry.key)
        ..add(entry.value);
    }
    for (final item in source.primaryFilters) {
      parts
        ..add(item.url)
        ..add(item.typeid)
        ..add(forumContentTextHash(item.label));
    }
    for (final item in source.typeFilters) {
      parts
        ..add(item.url)
        ..add(item.typeid)
        ..add(forumContentTextHash(item.label));
    }
    for (final item in source.subForums) {
      parts
        ..add(item.fid)
        ..add(item.url)
        ..add(forumContentTextHash(item.title));
    }
    for (final item in source.topEntries) {
      parts
        ..add(item.tid)
        ..add(item.url)
        ..add(forumContentTextHash(item.title))
        ..add(forumContentTextHash(item.badgeLabel));
    }
    for (final item in source.threads) {
      parts
        ..add(item.tid)
        ..add(item.typeid)
        ..add(item.uid)
        ..add(forumContentTextHash(item.subject))
        ..add(forumContentTextHash(item.excerpt))
        ..add(forumContentNullableTextHash(item.sourceTagName))
        ..add(forumContentNullableTextHash(item.badgeLabel))
        ..add(forumContentTextHash(item.dateline));
    }
    return forumContentSourceRevision(parts);
  }
}

final class ForumDisplayFilterProjection {
  const ForumDisplayFilterProjection({
    required this.source,
    required this.displayLabel,
  });

  factory ForumDisplayFilterProjection.raw(ForumDisplayFilterItem source) {
    return ForumDisplayFilterProjection(
      source: source,
      displayLabel: source.label,
    );
  }

  final ForumDisplayFilterItem source;
  final String displayLabel;
}

final class ForumDisplaySubForumProjection {
  const ForumDisplaySubForumProjection({
    required this.source,
    required this.displayTitle,
  });

  factory ForumDisplaySubForumProjection.raw(ForumDisplaySubForum source) {
    return ForumDisplaySubForumProjection(
      source: source,
      displayTitle: source.title,
    );
  }

  final ForumDisplaySubForum source;
  final String displayTitle;
}

final class ForumDisplayTopEntryProjection {
  const ForumDisplayTopEntryProjection({
    required this.source,
    required this.displayTitle,
    required this.displayBadgeLabel,
  });

  factory ForumDisplayTopEntryProjection.raw(ForumDisplayTopEntry source) {
    return ForumDisplayTopEntryProjection(
      source: source,
      displayTitle: source.title,
      displayBadgeLabel: source.badgeLabel,
    );
  }

  final ForumDisplayTopEntry source;
  final String displayTitle;
  final String displayBadgeLabel;
}

final class ForumDisplayThreadProjection {
  const ForumDisplayThreadProjection({
    required this.source,
    required this.displaySubject,
    required this.displayExcerpt,
    required this.displaySourceTagName,
    required this.displayBadgeLabel,
    required this.displayDateline,
  });

  factory ForumDisplayThreadProjection.raw(ForumThreadSummary source) {
    return ForumDisplayThreadProjection(
      source: source,
      displaySubject: source.subject,
      displayExcerpt: source.excerpt,
      displaySourceTagName: source.sourceTagName,
      displayBadgeLabel: source.badgeLabel,
      displayDateline: source.dateline,
    );
  }

  final ForumThreadSummary source;
  final String displaySubject;
  final String displayExcerpt;
  final String? displaySourceTagName;
  final String? displayBadgeLabel;
  final String displayDateline;
}
