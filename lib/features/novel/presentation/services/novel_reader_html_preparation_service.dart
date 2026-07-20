import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_flow_unit_extractor.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';

abstract interface class NovelReaderHtmlPreparationService {
  Future<NovelReaderPreparedChapter> prepare({
    required String rawHtml,
    required NovelEpisodeItem episode,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
    NovelReaderDocument? semanticDocument,
  });
}

final class DefaultNovelReaderHtmlPreparationService
    implements NovelReaderHtmlPreparationService {
  const DefaultNovelReaderHtmlPreparationService({
    this.preparer = const NovelHtmlChapterRenderPreparer(),
    this.flowUnitExtractor = const DefaultNovelReaderHtmlFlowUnitExtractor(),
  });

  final NovelHtmlChapterPreparer preparer;
  final NovelReaderHtmlFlowUnitExtractor flowUnitExtractor;

  @override
  Future<NovelReaderPreparedChapter> prepare({
    required String rawHtml,
    required NovelEpisodeItem episode,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
    NovelReaderDocument? semanticDocument,
  }) async {
    final prepared = await preparer.prepare(
      rawHtml: rawHtml,
      preferences: preferences,
      theme: theme,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
    );
    final flowUnits = flowUnitExtractor.extract(
      episodeId: episode.episodeId,
      renderDocument: prepared.document,
      semanticDocument: semanticDocument,
    );
    return NovelReaderPreparedChapter(
      episodeId: episode.episodeId,
      contentHash: _stableHash(prepared.document.preparedHtml),
      html: prepared.html,
      renderDocument: prepared.document,
      flowUnits: flowUnits,
      themeSignature: prepared.document.themeSignature,
      imageDimensionRevision: _imageDimensionRevision(prepared.document),
      convertedTextNodeCount: prepared.convertedTextNodeCount,
    );
  }

  int _imageDimensionRevision(ForumHtmlPreparedRenderDocument document) {
    var value = 0x811c9dc5;
    for (final entry in document.sequence.entries) {
      final dimensions = '${entry.url}|${entry.htmlWidth}|${entry.htmlHeight}';
      for (final unit in dimensions.codeUnits) {
        value ^= unit;
        value = (value * 0x01000193) & 0x7fffffff;
      }
    }
    return value;
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
