import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_legacy_markup_normalization.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_legacy_markup_normalizer.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

class NovelHtmlPreparedChapter {
  const NovelHtmlPreparedChapter({
    required this.html,
    required this.document,
    required this.convertedTextNodeCount,
    this.legacyMarkupNormalization =
        NovelReaderLegacyMarkupNormalizationSummary.none,
  });

  final String html;
  final ForumHtmlPreparedRenderDocument document;
  final int convertedTextNodeCount;
  final NovelReaderLegacyMarkupNormalizationSummary legacyMarkupNormalization;
}

abstract interface class NovelHtmlChapterPreparer {
  int get legacyMarkupNormalizerRevision;

  Future<NovelHtmlPreparedChapter> prepare({
    required String rawHtml,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  });
}

class NovelHtmlChapterRenderPreparer implements NovelHtmlChapterPreparer {
  const NovelHtmlChapterRenderPreparer({
    HtmlTextNodeConversionService? conversionService,
    NovelReaderLegacyMarkupNormalizer legacyMarkupNormalizer =
        const DefaultNovelReaderLegacyMarkupNormalizer(),
    ForumHtmlRenderPreparer renderPreparer =
        const DefaultForumHtmlRenderPreparer(),
  }) : _conversionService = conversionService,
       _legacyMarkupNormalizer = legacyMarkupNormalizer,
       _renderPreparer = renderPreparer;

  final HtmlTextNodeConversionService? _conversionService;
  final NovelReaderLegacyMarkupNormalizer _legacyMarkupNormalizer;
  final ForumHtmlRenderPreparer _renderPreparer;

  @override
  int get legacyMarkupNormalizerRevision => _legacyMarkupNormalizer.revision;

  @override
  Future<NovelHtmlPreparedChapter> prepare({
    required String rawHtml,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) async {
    var html = rawHtml;
    var convertedTextNodeCount = 0;
    if (preferences.conversionMode != TextConversionMode.none) {
      final conversionService =
          _conversionService ?? DomHtmlTextNodeConversionService();
      final converted = await conversionService.convert(
        html: rawHtml,
        converter: resolveTextConverter(preferences.conversionMode),
      );
      html = converted.html;
      convertedTextNodeCount = converted.convertedTextNodeCount;
    }
    final normalization = _legacyMarkupNormalizer.normalize(html);
    html = normalization.html;
    final document = _renderPreparer.prepare(
      html: html,
      preferences: preferences,
      theme: theme,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
    );
    return NovelHtmlPreparedChapter(
      html: html,
      document: document,
      convertedTextNodeCount: convertedTextNodeCount,
      legacyMarkupNormalization: normalization.summary,
    );
  }
}
