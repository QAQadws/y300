import 'dart:isolate';

import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_document_dto.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
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

  factory NovelReaderDocumentBuildRequest.fromMap(Map<String, Object?> map) {
    final rawParagraphs =
        map['fallbackParagraphs'] as List<Object?>? ?? const <Object?>[];
    return NovelReaderDocumentBuildRequest(
      episodeId: map['episodeId'] as String? ?? '',
      rawHtml: map['rawHtml'] as String? ?? '',
      fallbackParagraphs: rawParagraphs
          .map((item) => item?.toString() ?? '')
          .toList(growable: false),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'episodeId': episodeId,
      'rawHtml': rawHtml,
      'fallbackParagraphs': List<String>.from(
        fallbackParagraphs,
        growable: false,
      ),
    };
  }
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
    final requestMap = request.toMap();
    final dtoMap = await Isolate.run<Map<String, Object?>>(() {
      return _buildDocumentDtoMap(requestMap);
    });
    return NovelReaderDocumentDto.fromMap(dtoMap).toDocument();
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
  }) : _parser = parser,
       _executor = executor;

  static const int rawHtmlLengthThreshold = 12000;
  static const int fallbackParagraphCountThreshold = 80;

  final NovelReaderDocumentParser _parser;
  final NovelReaderDocumentBuildExecutor _executor;

  @override
  Future<NovelReaderDocument> build(
    NovelReaderDocumentBuildRequest request, {
    TextConverter converter = const IdentityTextConverter(),
  }) async {
    // Convert on the current isolate first: OpenCC uses a MethodChannel and
    // cannot run inside Isolate.run. IdentityTextConverter is a cheap no-op.
    final converted = await _convert(request, converter);
    if (_shouldBuildInBackground(converted)) {
      return _executor.buildInBackground(converted);
    }
    return _parser.parse(
      episodeId: converted.episodeId,
      rawHtml: converted.rawHtml,
      fallbackParagraphs: converted.fallbackParagraphs,
    );
  }

  Future<NovelReaderDocumentBuildRequest> _convert(
    NovelReaderDocumentBuildRequest request,
    TextConverter converter,
  ) async {
    if (converter.mode == TextConversionMode.none) {
      return request;
    }
    final convertedHtml = await converter.convertHtml(request.rawHtml);
    final convertedParagraphs = <String>[
      for (final paragraph in request.fallbackParagraphs)
        await converter.convertHtml(paragraph),
    ];
    return NovelReaderDocumentBuildRequest(
      episodeId: request.episodeId,
      rawHtml: convertedHtml,
      fallbackParagraphs: convertedParagraphs,
    );
  }

  bool _shouldBuildInBackground(NovelReaderDocumentBuildRequest request) {
    return request.rawHtml.length >= rawHtmlLengthThreshold ||
        request.fallbackParagraphs.length >= fallbackParagraphCountThreshold;
  }
}

Map<String, Object?> _buildDocumentDtoMap(Map<String, Object?> requestMap) {
  final parser = const DiscuzNovelReaderDocumentParser();
  final request = NovelReaderDocumentBuildRequest.fromMap(requestMap);
  final document = parser.parse(
    episodeId: request.episodeId,
    rawHtml: request.rawHtml,
    fallbackParagraphs: request.fallbackParagraphs,
  );
  return NovelReaderDocumentDto.fromDocument(document).toMap();
}
