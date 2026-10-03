import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';

void main() {
  test(
    'real isolate returns the same document without UI DTO reconstruction',
    () async {
      final request = NovelReaderDocumentBuildRequest(
        episodeId: 'fixture-background',
        rawHtml:
            '''
<h2>章节标题</h2>
<blockquote><b>引用粗体</b><i>引用斜体</i><font color="#ff0000">引用颜色</font><a href="forum.php?mod=viewthread&amp;tid=100">引用链接</a></blockquote>
<img aid="4567" width="800" height="1200" src="//bbs.yamibo.com/data/attachment/forum/novel.jpg" alt="插图">
${List.filled(180, '<p>正文<b>粗体</b><a href="https://example.org">链接</a></p>').join()}
''',
        fallbackParagraphs: const [],
      );
      final background = await const IsolateNovelReaderDocumentBuildExecutor()
          .buildInBackground(request);
      final local = const DiscuzNovelReaderDocumentParser().parse(
        episodeId: request.episodeId,
        rawHtml: request.rawHtml,
        fallbackParagraphs: request.fallbackParagraphs,
      );
      expect(background.rawHtmlHash, local.rawHtmlHash);
      expect(background.plainText, local.plainText);
      expect(
        background.blocks.map((block) => block.anchorId),
        local.blocks.map((block) => block.anchorId),
      );
      expect(background.wordCount, local.wordCount);

      final heading = background.blocks[0] as RichTextBlock;
      expect(heading.isHeading, isTrue);
      expect(heading.plainText, '章节标题');

      final quote = background.blocks[1] as RichQuoteBlock;
      final localQuote = local.blocks[1] as RichQuoteBlock;
      final quotedText = quote.blocks.single as RichTextBlock;
      final localQuotedText = localQuote.blocks.single as RichTextBlock;
      expect(quote.anchorId, localQuote.anchorId);
      expect(quotedText.anchorId, localQuotedText.anchorId);
      expect(quotedText.runs.first.isBold, isTrue);
      expect(quotedText.runs[1].isItalic, isTrue);
      expect(quotedText.runs[2].color, '#ff0000');
      expect(quotedText.runs.last.linkTid, '100');
      expect(quotedText.runs.last.linkUrl, localQuotedText.runs.last.linkUrl);

      final image = background.blocks[2] as RichImageBlock;
      final localImage = local.blocks[2] as RichImageBlock;
      expect(image.url, localImage.url);
      expect(image.rawUrl, localImage.rawUrl);
      expect(image.index, localImage.index);
      expect(image.aid, '4567');
      expect(image.altText, '插图');
      expect(image.originalWidth, 800);
      expect(image.originalHeight, 1200);
    },
  );

  test(
    'one very long fallback paragraph also uses the background executor',
    () async {
      final executor = _RecordingBuildExecutor();
      await AdaptiveNovelReaderDocumentBuildService(
        parser: const DiscuzNovelReaderDocumentParser(),
        executor: executor,
      ).build(
        NovelReaderDocumentBuildRequest(
          episodeId: 'fixture-fallback',
          rawHtml: '',
          fallbackParagraphs: [List.filled(13000, '文').join()],
        ),
      );
      expect(executor.callCount, 1);
    },
  );
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
