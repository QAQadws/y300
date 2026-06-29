import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';

void main() {
  test('small request builds on current isolate', () async {
    final executor = _RecordingBuildExecutor();
    final service = AdaptiveNovelReaderDocumentBuildService(
      parser: const DiscuzNovelReaderDocumentParser(),
      executor: executor,
    );

    final document = await service.build(
      const NovelReaderDocumentBuildRequest(
        episodeId: 'ep1',
        rawHtml: '<p>第一段</p><p>第二段</p>',
        fallbackParagraphs: <String>['第一段', '第二段'],
      ),
    );

    expect(executor.callCount, 0);
    expect(document.blocks, hasLength(2));
    expect((document.blocks.first as RichTextBlock).novelPlainText, '第一段');
  });

  test('large request builds through async executor', () async {
    final executor = _RecordingBuildExecutor();
    final service = AdaptiveNovelReaderDocumentBuildService(
      parser: const DiscuzNovelReaderDocumentParser(),
      executor: executor,
    );

    final document = await service.build(
      NovelReaderDocumentBuildRequest(
        episodeId: 'ep-large',
        rawHtml: '<p>${List<String>.filled(13000, '文').join()}</p>',
        fallbackParagraphs: const <String>['回退段落'],
      ),
    );

    expect(executor.callCount, 1);
    expect(document.episodeId, 'ep-large');
    expect(document.plainText.trim(), isNotEmpty);
  });

  test('empty html still falls back to paragraphs', () async {
    final service = AdaptiveNovelReaderDocumentBuildService(
      parser: const DiscuzNovelReaderDocumentParser(),
      executor: _RecordingBuildExecutor(),
    );

    final document = await service.build(
      const NovelReaderDocumentBuildRequest(
        episodeId: 'ep-fallback',
        rawHtml: '   ',
        fallbackParagraphs: <String>['第一段', '第二段'],
      ),
    );

    expect(document.blocks, hasLength(2));
    expect(document.plainText, '第一段\n第二段');
  });
}

class _RecordingBuildExecutor implements NovelReaderDocumentBuildExecutor {
  int callCount = 0;

  @override
  Future<NovelReaderDocument> buildInBackground(
    NovelReaderDocumentBuildRequest request,
  ) async {
    callCount += 1;
    return const DiscuzNovelReaderDocumentParser().parse(
      episodeId: request.episodeId,
      rawHtml: request.rawHtml,
      fallbackParagraphs: request.fallbackParagraphs,
    );
  }
}
