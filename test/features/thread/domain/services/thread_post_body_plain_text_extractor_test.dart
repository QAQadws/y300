import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_plain_text_extractor.dart';

void main() {
  group('ThreadPostBodyPlainTextExtractor', () {
    test('extracts text, link text and quote text in order', () {
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(
            runs: <RichRun>[
              RichRun(text: '第一段 '),
              RichRun(
                text: '链接文本',
                linkUrl: 'https://bbs.yamibo.com/thread-1-1-1.html',
              ),
            ],
          ),
          RichQuoteBlock(
            blocks: <RichBlock>[
              RichTextBlock(runs: <RichRun>[RichRun(text: '引用正文')]),
            ],
          ),
          RichTextBlock(runs: <RichRun>[RichRun(text: '尾段')]),
        ],
      );

      final text = const ThreadPostBodyPlainTextExtractor().extract(document);

      expect(text, '第一段 链接文本\n\n引用正文\n\n尾段');
    });

    test('omits block images and keeps inline smiley alt text', () {
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(
            runs: <RichRun>[
              RichRun(text: '喜欢'),
              RichRun(
                text: '',
                inlineImage: RichInlineImage(
                  url: 'https://bbs.yamibo.com/static/image/smiley/a.gif',
                  rawUrl: 'static/image/smiley/a.gif',
                  altText: '[笑]',
                ),
              ),
              RichRun(
                text: '',
                inlineImage: RichInlineImage(
                  url: 'https://bbs.yamibo.com/static/image/smiley/b.gif',
                  rawUrl: 'static/image/smiley/b.gif',
                ),
              ),
            ],
          ),
          RichImageBlock(
            url: 'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
            rawUrl: 'data/attachment/forum/page.jpg',
            index: 0,
          ),
          RichTextBlock(runs: <RichRun>[RichRun(text: '尾巴')]),
        ],
      );

      final text = const ThreadPostBodyPlainTextExtractor().extract(document);

      expect(text, '喜欢[笑]\n尾巴');
    });

    test('can copy block image placeholders or urls', () {
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(runs: <RichRun>[RichRun(text: '前文')]),
          RichImageBlock(
            url: 'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
            rawUrl: 'data/attachment/forum/page.jpg',
            index: 0,
          ),
          RichTextBlock(runs: <RichRun>[RichRun(text: '后文')]),
        ],
      );

      final extractor = const ThreadPostBodyPlainTextExtractor();

      expect(
        extractor.extract(
          document,
          options: const ThreadPostPlainTextExtractOptions(
            blockImagePolicy: ThreadPostBlockImageTextPolicy.placeholder,
          ),
        ),
        '前文\n[图片]\n后文',
      );
      expect(
        extractor.extract(
          document,
          options: const ThreadPostPlainTextExtractOptions(
            blockImagePolicy: ThreadPostBlockImageTextPolicy.url,
          ),
        ),
        '前文\nhttps://bbs.yamibo.com/data/attachment/forum/page.jpg\n后文',
      );
    });

    test('supports inline image title fallback and url policy', () {
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(
            runs: <RichRun>[
              RichRun(text: 'A'),
              RichRun(
                text: '',
                inlineImage: RichInlineImage(
                  url: 'https://bbs.yamibo.com/static/image/smiley/a.gif',
                  rawUrl: 'static/image/smiley/a.gif',
                  titleText: '开心',
                ),
              ),
              RichRun(text: 'B'),
            ],
          ),
        ],
      );

      final extractor = const ThreadPostBodyPlainTextExtractor();

      expect(extractor.extract(document), 'A开心B');
      expect(
        extractor.extract(
          document,
          options: const ThreadPostPlainTextExtractOptions(
            inlineImagePolicy: ThreadPostInlineImageTextPolicy.url,
          ),
        ),
        'Ahttps://bbs.yamibo.com/static/image/smiley/a.gifB',
      );
      expect(
        extractor.extract(
          document,
          options: const ThreadPostPlainTextExtractOptions(
            inlineImagePolicy: ThreadPostInlineImageTextPolicy.omit,
          ),
        ),
        'AB',
      );
    });

    test('uses link url only when display text is empty', () {
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(
            runs: <RichRun>[
              RichRun(
                text: '',
                linkUrl: 'https://bbs.yamibo.com/thread-1-1-1.html',
              ),
            ],
          ),
        ],
      );

      final text = const ThreadPostBodyPlainTextExtractor().extract(document);

      expect(text, 'https://bbs.yamibo.com/thread-1-1-1.html');
    });

    test('can prefix quote lines', () {
      const document = RichDocument(
        blocks: <RichBlock>[
          RichQuoteBlock(
            blocks: <RichBlock>[
              RichTextBlock(runs: <RichRun>[RichRun(text: '引用一')]),
              RichTextBlock(runs: <RichRun>[RichRun(text: '引用二')]),
            ],
          ),
        ],
      );

      final text = const ThreadPostBodyPlainTextExtractor().extract(
        document,
        options: const ThreadPostPlainTextExtractOptions(
          quotePolicy: ThreadPostQuoteTextPolicy.prefixLines,
        ),
      );

      expect(text, '> 引用一\n> 引用二');
    });
  });
}
