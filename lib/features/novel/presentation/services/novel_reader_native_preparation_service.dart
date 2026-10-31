import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

import '../models/novel_reader_native_prepared_chapter.dart';
import 'novel_reader_background_work.dart';
import 'novel_reader_native_anchor_binder.dart';
import 'novel_reader_pagination_cancellation.dart';

abstract interface class NovelReaderNativePreparationService {
  Future<NovelReaderNativeChapterPreparation> prepare({
    required String episodeId,
    required String sourceId,
    required String rawHtml,
    required NovelReaderDocument semanticDocument,
    required NovelReaderPaginationCancellationToken cancellation,
    TextConverter converter,
  });
}

/// Converted HTML and semantic origins refer to the same actual input. No
/// prepared legacy HTML/normalization is inserted between their DOM paths.
final class NovelReaderNativeChapterBuildRequest {
  const NovelReaderNativeChapterBuildRequest({
    required this.episodeId,
    required this.sourceId,
    required this.convertedHtml,
    required this.semanticDocument,
    required this.convertedTextNodeCount,
  });
  final String episodeId;
  final String sourceId;
  final String convertedHtml;
  final NovelReaderDocument semanticDocument;
  final int convertedTextNodeCount;
}

abstract interface class NovelReaderNativeChapterBuildExecutor {
  Future<NovelReaderNativeChapterPreparation> build(
    NovelReaderNativeChapterBuildRequest request,
  );
}

final class AdaptiveNovelReaderNativeChapterBuildExecutor
    implements NovelReaderNativeChapterBuildExecutor {
  const AdaptiveNovelReaderNativeChapterBuildExecutor();

  @override
  Future<NovelReaderNativeChapterPreparation> build(
    NovelReaderNativeChapterBuildRequest request,
  ) => NovelReaderBackgroundWork.run(
    codeUnits: request.convertedHtml.length,
    // Only immutable source/semantic values cross the worker boundary.
    transform: () => _build(request),
  );
}

final class DefaultNovelReaderNativePreparationService
    implements NovelReaderNativePreparationService {
  const DefaultNovelReaderNativePreparationService({
    HtmlTextNodeConversionService? conversionService,
    this.executor = const AdaptiveNovelReaderNativeChapterBuildExecutor(),
  }) : _conversionService = conversionService;
  final HtmlTextNodeConversionService? _conversionService;
  final NovelReaderNativeChapterBuildExecutor executor;

  @override
  Future<NovelReaderNativeChapterPreparation> prepare({
    required String episodeId,
    required String sourceId,
    required String rawHtml,
    required NovelReaderDocument semanticDocument,
    required NovelReaderPaginationCancellationToken cancellation,
    TextConverter converter = const IdentityTextConverter(),
  }) async {
    cancellation.throwIfCancelled();
    _validate(episodeId, sourceId, semanticDocument, converter.mode.name);
    var html = rawHtml;
    var convertedCount = 0;
    if (converter.mode != TextConversionMode.none) {
      // OpenCC is a Host channel operation. Share the existing conversion
      // service/cache with semantic building; never invoke it in Isolate.run.
      final converted = await cancellation.waitFor(
        (_conversionService ?? DomHtmlTextNodeConversionService()).convert(
          html: rawHtml,
          converter: converter,
        ),
      );
      cancellation.throwIfCancelled();
      html = converted.html;
      convertedCount = converted.convertedTextNodeCount;
    }
    final result = await cancellation.waitFor(
      executor.build(
        NovelReaderNativeChapterBuildRequest(
          episodeId: episodeId,
          sourceId: sourceId,
          // Semantic parser records the exact trimmed parse input hash.
          convertedHtml: html.trim(),
          semanticDocument: semanticDocument,
          convertedTextNodeCount: convertedCount,
        ),
      ),
    );
    cancellation.throwIfCancelled();
    return result;
  }
}

void _validate(
  String episodeId,
  String sourceId,
  NovelReaderDocument semantic,
  String conversion,
) {
  if (episodeId.isEmpty ||
      sourceId.isEmpty ||
      semantic.episodeId != episodeId) {
    throw const NovelReaderNativeAnchorBindingException(
      NovelReaderNativeAnchorBindingFailure.identity,
    );
  }
  if (semantic.textConversionIdentity != conversion) {
    throw const NovelReaderNativeAnchorBindingException(
      NovelReaderNativeAnchorBindingFailure.conversion,
    );
  }
}

NovelReaderNativeChapterPreparation _build(
  NovelReaderNativeChapterBuildRequest request,
) {
  final semantic = request.semanticDocument;
  final conversion = semantic.textConversionIdentity;
  _validate(request.episodeId, request.sourceId, semantic, conversion ?? '');
  if (conversion == null) {
    throw const NovelReaderNativeAnchorBindingException(
      NovelReaderNativeAnchorBindingFailure.conversion,
    );
  }
  final body = const ForumBodyParser().parse(
    html: request.convertedHtml,
    sourceId: request.sourceId,
    conversionIdentity: conversion,
  );
  if (request.convertedHtml.isEmpty &&
      semantic.blocks.isEmpty &&
      semantic.plainText.isEmpty) {
    return NovelReaderNativeEmptyChapter(
      episodeId: request.episodeId,
      convertedTextNodeCount: request.convertedTextNodeCount,
      identity: body.identity,
    );
  }
  final anchors = const NovelReaderNativeAnchorBinder().bind(
    episodeId: request.episodeId,
    sourceId: request.sourceId,
    semanticDocument: semantic,
    bodyDocument: body,
  );
  return NovelReaderNativePreparedChapter(
    episodeId: request.episodeId,
    convertedTextNodeCount: request.convertedTextNodeCount,
    document: body,
    anchors: anchors,
  );
}
