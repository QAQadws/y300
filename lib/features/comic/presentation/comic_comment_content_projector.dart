import 'package:y300/features/thread/presentation/thread_post_text_slots.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projector.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_content_projection_batch_executor.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

final class ComicCommentContentProjector {
  const ComicCommentContentProjector({
    required this.plainTextBatchConversionService,
    required this.htmlTextNodeConversionService,
    required this.diagnosticRecorder,
  });

  final PlainTextBatchConversionService plainTextBatchConversionService;
  final HtmlTextNodeConversionService htmlTextNodeConversionService;
  final TextConversionDiagnosticRecorder diagnosticRecorder;

  Future<ComicCommentContentProjection> project({
    required ComicCommentSessionKey sessionKey,
    required ComicCommentLoadResult source,
    required TextConverter converter,
    String? sourceRevision,
  }) async {
    final revision =
        sourceRevision ??
        sourceRevisionFor(sessionKey: sessionKey, source: source);
    if (converter.mode == TextConversionMode.none || source.items.isEmpty) {
      return ComicCommentContentProjection.raw(
        source,
        mode: converter.mode,
        converterId: converter.id,
        sourceRevision: revision,
      );
    }

    final collector = ThreadPlainTextCollector();
    final slots = [
      for (final item in source.items)
        ThreadPostTextSlots.collect(item.post, collector),
    ];
    final batch =
        await TextContentProjectionBatchExecutor(
          plainTextBatchConversionService: plainTextBatchConversionService,
          htmlTextNodeConversionService: htmlTextNodeConversionService,
          diagnosticRecorder: diagnosticRecorder,
        ).convert(
          surface: TextConversionSurface.comicComments,
          plainSources: collector.sources,
          htmlFragments: [for (final item in source.items) item.rawMessage],
          converter: converter,
          sourceRevision: revision,
        );
    if (!batch.succeeded ||
        batch.plainValues.length != collector.sources.length ||
        batch.htmlValues.length != source.items.length) {
      return ComicCommentContentProjection.raw(
        source,
        mode: converter.mode,
        converterId: converter.id,
        sourceRevision: revision,
      );
    }

    return ComicCommentContentProjection(
      sourceResult: source,
      items: [
        for (var index = 0; index < source.items.length; index += 1)
          ComicCommentItemProjection(
            sourceItem: source.items[index],
            displayMessage: batch.htmlValues[index].html,
            displayDateline: slots[index].dateline.value(batch.plainValues),
            projectedPost: slots[index].build(
              source.items[index].post,
              values: batch.plainValues,
              displayHtml: batch.htmlValues[index].html,
            ),
          ),
      ],
      mode: converter.mode,
      converterId: converter.id,
      sourceRevision: revision,
      isConverted: true,
    );
  }

  static String sourceRevisionFor({
    required ComicCommentSessionKey sessionKey,
    required ComicCommentLoadResult source,
  }) {
    final loadedPages = source.loadedPages.toList()..sort();
    final parts = <Object?>[
      sessionKey.episodeId,
      sessionKey.sourceTid,
      source.sourceTid,
      source.status.name,
      source.expectedPages,
      source.errorCode?.name,
      ...loadedPages,
    ];
    for (final item in source.items) {
      parts.addAll(ThreadDetailContentProjector.postRevisionParts(item.post));
      parts.addAll(<Object?>[
        item.pid,
        item.authorId,
        _textHash(item.authorName),
        item.floorNumber,
        _textHash(item.dateline),
        _textHash(item.rawMessage),
        _textHash(item.avatarUrl),
      ]);
    }
    return 'comic-comments:${Object.hashAll(parts)}';
  }

  static int _textHash(String? value) => Object.hashAll(<Object?>[value ?? '']);
}
