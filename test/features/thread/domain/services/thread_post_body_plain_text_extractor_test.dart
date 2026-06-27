import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_plain_text_extractor.dart';

void main() {
  group('ThreadPostBodyPlainTextExtractor', () {
    test('extracts text, link text and quote text in order', () {
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[
              ThreadPostTextRun(text: '第一段 '),
              ThreadPostTextRun(
                text: '链接文本',
                linkUrl: 'https://bbs.yamibo.com/thread-1-1-1.html',
              ),
            ],
          ),
          ThreadPostQuoteBlock(
            blocks: <ThreadPostBodyBlock>[
              ThreadPostTextBlock(
                runs: <ThreadPostTextRun>[ThreadPostTextRun(text: '引用正文')],
              ),
            ],
          ),
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: '尾段')],
          ),
        ],
      );

      final text = const ThreadPostBodyPlainTextExtractor().extract(document);

      expect(text, '第一段 链接文本\n引用正文\n尾段');
    });

    test('omits block images and keeps inline smiley alt text', () {
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[
              ThreadPostTextRun(text: '喜欢'),
              ThreadPostTextRun(
                text: '',
                inlineImage: ThreadPostInlineImage(
                  url: 'https://bbs.yamibo.com/static/image/smiley/a.gif',
                  rawUrl: 'static/image/smiley/a.gif',
                  altText: '[笑]',
                ),
              ),
              ThreadPostTextRun(
                text: '',
                inlineImage: ThreadPostInlineImage(
                  url: 'https://bbs.yamibo.com/static/image/smiley/b.gif',
                  rawUrl: 'static/image/smiley/b.gif',
                ),
              ),
            ],
          ),
          ThreadPostImageBlock(
            url: 'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
            rawUrl: 'data/attachment/forum/page.jpg',
            index: 0,
          ),
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: '尾巴')],
          ),
        ],
      );

      final text = const ThreadPostBodyPlainTextExtractor().extract(document);

      expect(text, '喜欢[笑]\n尾巴');
    });
  });
}
