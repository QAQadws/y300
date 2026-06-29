import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_document_view.dart';

void main() {
  testWidgets('NovelReaderDocumentView renders rich blocks', (tester) async {
    final tappedLinks = <NovelReaderLink>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderDocumentView(
          document: _document(
            blocks: const <RichBlock>[
              RichTextBlock(
                anchorId: 'p',
                runs: <RichRun>[RichRun(text: '正文')],
              ),
              RichTextBlock(
                anchorId: 'h',
                headingLevel: 1,
                runs: <RichRun>[RichRun(text: '标题')],
              ),
              RichQuoteBlock(
                anchorId: 'q',
                blocks: <RichBlock>[
                  RichTextBlock(
                    anchorId: 'q',
                    runs: <RichRun>[RichRun(text: '引用')],
                  ),
                ],
              ),
              RichDividerBlock(anchorId: 'd'),
              RichTextBlock(
                anchorId: 'l',
                runs: <RichRun>[
                  RichRun(text: '链接', linkUrl: 'https://example.com'),
                ],
              ),
            ],
          ),
          typography: _typography(),
          paragraphSpacing: 8,
          onLinkTap: tappedLinks.add,
        ),
      ),
    );

    expect(find.text('正文'), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
    expect(find.text('引用'), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-node-d')), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-reader-link-block')));
    expect(tappedLinks.single.text, '链接');
  });

  testWidgets('NovelReaderDocumentView handles inline paragraph links', (
    tester,
  ) async {
    final tappedLinks = <NovelReaderLink>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderDocumentView(
          document: _document(
            blocks: const <RichBlock>[
              RichTextBlock(
                anchorId: 'p',
                runs: <RichRun>[
                  RichRun(text: '前文 '),
                  RichRun(text: '链接', linkUrl: 'https://example.com'),
                  RichRun(text: ' 后文'),
                ],
              ),
            ],
          ),
          typography: _typography(),
          paragraphSpacing: 8,
          onLinkTap: tappedLinks.add,
        ),
      ),
    );

    expect(find.textContaining('前文'), findsOneWidget);
    await tester.tap(find.text('链接'));

    expect(tappedLinks.single.url, 'https://example.com');
  });

  testWidgets('NovelReaderDocumentView renders images with header builder', (
    tester,
  ) async {
    const headerBuilder = _StaticImageHeaderBuilder(<String, String>{
      'Cookie': 'auth=token',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderDocumentView(
          document: const NovelReaderDocument(
            episodeId: 'ep1',
            rawHtmlHash: 'hash',
            plainText: '',
            wordCount: 0,
            body: RichDocument(
              blocks: <RichBlock>[
                RichImageBlock(
                  anchorId: 'img',
                  url: 'https://img.test/novel.jpg',
                  rawUrl: 'novel.jpg',
                  index: 0,
                  altText: '插图',
                ),
              ],
            ),
          ),
          typography: _TestTypography.value,
          paragraphSpacing: 8,
          imageHeaderBuilder: headerBuilder,
        ),
      ),
    );

    expect(find.byType(LibraryCachedImage), findsOneWidget);
    final image = tester.widget<LibraryCachedImage>(find.byType(LibraryCachedImage));
    expect(image.imageUrl, 'https://img.test/novel.jpg');
    expect(image.headerBuilder, headerBuilder);
  });

  testWidgets('NovelReaderDocumentView accepts highlighted search result', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderDocumentView(
          document: _document(
            blocks: const <RichBlock>[
              RichTextBlock(
                anchorId: 'p',
                runs: <RichRun>[RichRun(text: '关键词在这里')],
              ),
            ],
          ),
          typography: _typography(),
          paragraphSpacing: 8,
          highlightedResult: const NovelReaderSearchResult(
            resultId: 'r1',
            keyword: '关键词',
            anchor: NovelReaderTextAnchor(episodeId: 'ep1', nodeId: 'p'),
            snippet: '关键词在这里',
            matchStart: 0,
            matchEnd: 3,
            nodeId: 'p',
          ),
        ),
      ),
    );

    expect(find.textContaining('关键词在这里'), findsOneWidget);
  });
}

NovelReaderDocument _document({required List<RichBlock> blocks}) {
  return NovelReaderDocument(
    episodeId: 'ep1',
    rawHtmlHash: 'hash',
    body: RichDocument(blocks: blocks),
    plainText: '',
    wordCount: 0,
  );
}

NovelReaderTypography _typography() => _TestTypography.value;

class _TestTypography {
  static const value = NovelReaderTypography(
    body: TextStyle(fontSize: 18),
    chapterTitle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
    quote: TextStyle(fontSize: 18, color: Colors.grey),
    link: TextStyle(fontSize: 18, color: Colors.blue),
    textAlign: TextAlign.start,
    firstLineIndent: 0,
    contentMaxWidth: 720,
  );
}

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder(this.headers);

  final Map<String, String> headers;

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async => headers;
}
