import 'dart:isolate';

import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

class NovelReaderDocumentBuildRequest {
  const NovelReaderDocumentBuildRequest({
    required this.episodeId,
    required this.rawHtml,
    required this.fallbackParagraphs,
  });

  final String episodeId;
  final String rawHtml;
  final List<String> fallbackParagraphs;
}

abstract interface class NovelReaderDocumentBuildExecutor {
  Future<NovelReaderDocument> buildInBackground(
    NovelReaderDocumentBuildRequest request,
  );
}

class IsolateNovelReaderDocumentBuildExecutor
    implements NovelReaderDocumentBuildExecutor {
  const IsolateNovelReaderDocumentBuildExecutor();

  @override
  Future<NovelReaderDocument> buildInBackground(
    NovelReaderDocumentBuildRequest request,
  ) async {
    // The document contains data only. Isolate.run transfers ownership on exit;
    // encoding a DTO then decoding its entire block tree on UI undoes that win.
    return Isolate.run(() => _buildDocument(request));
  }
}

abstract interface class NovelReaderDocumentBuildService {
  /// Builds a reader document. When [converter] performs real conversion its
  /// async [TextConverter.convertHtml] runs on the current isolate before
  /// parsing (OpenCC relies on a MethodChannel and cannot run in Isolate.run).
  Future<NovelReaderDocument> build(
    NovelReaderDocumentBuildRequest request, {
    TextConverter converter,
  });
}

class AdaptiveNovelReaderDocumentBuildService
    implements NovelReaderDocumentBuildService {
  const AdaptiveNovelReaderDocumentBuildService({
    required NovelReaderDocumentParser parser,
    NovelReaderDocumentBuildExecutor executor =
        const IsolateNovelReaderDocumentBuildExecutor(),
    HtmlTextNodeConversionService? htmlConversionService,
    PlainTextBatchConversionService? paragraphConversionService,
  }) : _parser = parser,
       _executor = executor,
       _htmlConversionService = htmlConversionService,
       _paragraphConversionService = paragraphConversionService;

  static const int rawHtmlLengthThreshold = 12000;
  static const int fallbackParagraphCountThreshold = 80;

  final NovelReaderDocumentParser _parser;
  final NovelReaderDocumentBuildExecutor _executor;
  final HtmlTextNodeConversionService? _htmlConversionService;
  final PlainTextBatchConversionService? _paragraphConversionService;

  @override
  Future<NovelReaderDocument> build(
    NovelReaderDocumentBuildRequest request, {
    TextConverter converter = const IdentityTextConverter(),
  }) async {
    // Convert on the current isolate first: OpenCC uses a MethodChannel and
    // cannot run inside Isolate.run. IdentityTextConverter is a cheap no-op.
    final converted = await _convert(request, converter);
    final NovelReaderDocument document;
    if (_shouldBuildInBackground(converted)) {
      document = await _executor.buildInBackground(converted);
    } else {
      document = _parser.parse(
        episodeId: converted.episodeId,
        rawHtml: converted.rawHtml,
        fallbackParagraphs: converted.fallbackParagraphs,
      );
    }
    return NovelReaderDocument(
      episodeId: document.episodeId,
      rawHtmlHash: document.rawHtmlHash,
      body: document.body,
      plainText: document.plainText,
      wordCount: document.wordCount,
      textConversionIdentity: converter.mode.name,
    );
  }

  Future<NovelReaderDocumentBuildRequest> _convert(
    NovelReaderDocumentBuildRequest request,
    TextConverter converter,
  ) async {
    if (converter.mode == TextConversionMode.none) {
      return request;
    }
    // Semantic and visible HTML must use the same text-node conversion policy.
    // The injected service also lets visual preparation reuse this conversion.
    final convertedHtml =
        await (_htmlConversionService ?? DomHtmlTextNodeConversionService())
            .convert(html: request.rawHtml, converter: converter);
    final convertedParagraphs =
        await (_paragraphConversionService ??
                DefaultPlainTextBatchConversionService())
            .convertAll(
              sources: request.fallbackParagraphs,
              converter: converter,
            );
    return NovelReaderDocumentBuildRequest(
      episodeId: request.episodeId,
      rawHtml: convertedHtml.html,
      fallbackParagraphs: convertedParagraphs,
    );
  }

  bool _shouldBuildInBackground(NovelReaderDocumentBuildRequest request) {
    return request.rawHtml.length >= rawHtmlLengthThreshold ||
        request.fallbackParagraphs.length >= fallbackParagraphCountThreshold ||
        request.fallbackParagraphs.fold<int>(
              0,
              (sum, text) => sum + text.length,
            ) >=
            rawHtmlLengthThreshold;
  }
}

NovelReaderDocument _buildDocument(NovelReaderDocumentBuildRequest request) {
  const parser = DiscuzNovelReaderDocumentParser();
  return parser.parse(
    episodeId: request.episodeId,
    rawHtml: request.rawHtml,
    fallbackParagraphs: request.fallbackParagraphs,
  );
}
