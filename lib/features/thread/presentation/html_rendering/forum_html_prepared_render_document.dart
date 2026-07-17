import 'package:flutter/foundation.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_adaptation_result.dart';

const forumHtmlReadableImageIndexAttribute = 'data-y300-readable-image-index';

@immutable
class ForumHtmlPreparedRenderDocument {
  const ForumHtmlPreparedRenderDocument({
    required this.preparedHtml,
    required this.sequence,
    required this.attachmentIdsByUrl,
    required this.totalImageCount,
    required this.skippedStickerCount,
    required this.skippedNonNetworkCount,
    required this.duplicatedReadableUrlCount,
    required this.attachmentTaggedCount,
    required this.themeSignature,
    required this.themeAdaptationStats,
  });

  final String preparedHtml;
  final ForumHtmlReadableImageSequence sequence;
  final Map<String, String> attachmentIdsByUrl;
  final int totalImageCount;
  final int skippedStickerCount;
  final int skippedNonNetworkCount;
  final int duplicatedReadableUrlCount;
  final int attachmentTaggedCount;
  final String themeSignature;
  final ForumHtmlThemeAdaptationStats themeAdaptationStats;

  int get readableImageCount => sequence.entries.length;

  ForumHtmlPreparedRenderDocument copyWith({String? preparedHtml}) {
    return ForumHtmlPreparedRenderDocument(
      preparedHtml: preparedHtml ?? this.preparedHtml,
      sequence: sequence,
      attachmentIdsByUrl: attachmentIdsByUrl,
      totalImageCount: totalImageCount,
      skippedStickerCount: skippedStickerCount,
      skippedNonNetworkCount: skippedNonNetworkCount,
      duplicatedReadableUrlCount: duplicatedReadableUrlCount,
      attachmentTaggedCount: attachmentTaggedCount,
      themeSignature: themeSignature,
      themeAdaptationStats: themeAdaptationStats,
    );
  }
}

@immutable
class ForumHtmlReadableImageSequence {
  const ForumHtmlReadableImageSequence({
    required this.sourceId,
    required this.entries,
  });

  final String sourceId;
  final List<ForumHtmlReadableImageEntry> entries;

  ForumHtmlReadableImageEntry? entryAt(int index) {
    if (index < 0 || index >= entries.length) {
      return null;
    }
    return entries[index];
  }
}

@immutable
class ForumHtmlReadableImageEntry {
  const ForumHtmlReadableImageEntry({
    required this.index,
    required this.url,
    required this.rawSrc,
    required this.cacheKey,
    required this.spec,
    this.attachmentId,
    this.alt,
    this.title,
    this.htmlWidth,
    this.htmlHeight,
  });

  final int index;
  final String url;
  final String rawSrc;
  final String cacheKey;
  final ForumImageLoadSpec spec;
  final String? attachmentId;
  final String? alt;
  final String? title;
  final double? htmlWidth;
  final double? htmlHeight;
}
