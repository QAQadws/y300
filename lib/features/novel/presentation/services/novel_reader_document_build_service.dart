import 'dart:isolate';

import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_document_dto.dart';

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
  Future<NovelReaderDocument> build(
    NovelReaderDocumentBuildRequest request,
  );
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
    NovelReaderDocumentBuildRequest request,
  ) {
    if (_shouldBuildInBackground(request)) {
      return _executor.buildInBackground(request);
    }
    return Future<NovelReaderDocument>.value(
      _parser.parse(
        episodeId: request.episodeId,
        rawHtml: request.rawHtml,
        fallbackParagraphs: request.fallbackParagraphs,
      ),
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
