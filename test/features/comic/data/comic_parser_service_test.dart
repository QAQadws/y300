import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/services/comic_parser_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/thread/data/services/thread_detail_html_parser.dart';

void main() {
  group('HtmlComicParserService', () {
    test('extracts images and episode links with deduplication', () {
      final parser = HtmlComicParserService();
      final result = parser.parse(
        message: '''
<div>\u4f5c\u8005: \u6d4b\u8bd5\u7ec4</div>
<img src="https://img.test/1.jpg" />
<img src="https://img.test/1.jpg" />
<img src="https://img.test/smilies/face.png" />
<a href="https://bbs.yamibo.com/thread-100-1-1.html?from=foo">1</a>
<a href="thread-101-1-1.html">\u7b2c2\u8bdd</a>
<a href="https://bbs.yamibo.com/thread-200-1-1.html">\u76ee\u5f55</a>
''',
      );

      expect(result.imageUrls.length, 1);
      expect(result.imageUrls.first, 'https://img.test/1.jpg');
      expect(result.episodeLinks.length, 3);
      expect(
        result.episodeLinks.first.url,
        'https://bbs.yamibo.com/thread-100-1-1.html',
      );
      expect(result.episodeLinks.first.episodeTitle, '1');
      expect(result.catalogUrl, 'https://bbs.yamibo.com/thread-200-1-1.html');
      expect(result.inferredAuthor, '\u6d4b\u8bd5\u7ec4');
      expect(
        result.plainTextSummary,
        contains('\u4f5c\u8005: \u6d4b\u8bd5\u7ec4'),
      );
      expect(result.parsingDebug, isNotNull);
      expect(result.parsingDebug!.totalEpisodeLinks, 3);
    });

    test('extracts forum.php viewthread links including escaped ampersands', () {
      final parser = HtmlComicParserService();
      final result = parser.parse(
        message: '''
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=530646&amp;amp;highlight=%E5%B9%B3%E8%89%AF%E6%B7%B1">01</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=533029&amp;amp;highlight=%E5%B9%B3%E8%89%AF%E6%B7%B1">02</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=533956&amp;amp;highlight=%E5%B9%B3%E8%89%AF%E6%B7%B1">03</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=537155&amp;amp;highlight=%E5%B9%B3%E8%89%AF%E6%B7%B1">04</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=539770&amp;amp;highlight=%E5%B9%B3%E8%89%AF%E6%B7%B1">05</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=542082&amp;amp;highlight=%E5%B9%B3%E8%89%AF%E6%B7%B1">06</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=542083&amp;amp;highlight=%E5%B9%B3%E8%89%AF%E6%B7%B1">07</a>
<a href="https://bbs.yamibo.com/thread-543780-1-1.html">08</a>
<a href="https://bbs.yamibo.com/thread-544245-1-1.html">09</a>
<a href="https://bbs.yamibo.com/thread-544320-1-1.html?_dsign=d63adfb8">\u7b2c\u4e00\u5377\u7279\u5178</a>
<a href="https://bbs.yamibo.com/thread-545243-1-1.html">10</a>
<a href="https://bbs.yamibo.com/thread-546436-1-1.html">\u7b2c\u4e8c\u5377\u7279\u5178</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=554347&amp;amp;fromuid=360078">\u7b2c\u4e09\u5377\u7279\u5178</a>
<a href="https://bbs.yamibo.com/thread-562720-1-1.html">23</a>
''',
      );

      expect(result.episodeLinks.length, 14);
      expect(
        result.episodeLinks.first.url,
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=530646',
      );
      expect(result.episodeLinks.first.episodeTitle, '01');
      expect(
        result.episodeLinks
            .where((e) => e.rawText == '\u7b2c\u4e09\u5377\u7279\u5178')
            .single
            .url,
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=554347&fromuid=360078',
      );
    });

    test('ignores legacy GBK highlight while parsing old comic post links', () {
      final parser = HtmlComicParserService();
      final result = parser.parse(
        message: '''
图源：<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=524596&amp;amp;highlight=%D2%B2%CE%DE%B7%E7%D3%EA">旧编码图源</a><br />
<a href="https://bbs.yamibo.com/thread-527284-1-1.html">16话后篇</a>
<a href="https://bbs.yamibo.com/thread-527285-1-1.html">17话</a>
<a href="https://bbs.yamibo.com/thread-527287-1-1.html">18话前篇</a>
<a href="https://bbs.yamibo.com/thread-527288-1-1.html">18话后篇</a>
<div class="img"><img src="https://bbs.yamibo.com/data/attachment/forum/202206/20/160615ywmwwnu65hzcp615.png" /></div>
<div class="img"><img src="https://bbs.yamibo.com/data/attachment/forum/202206/20/160617ttbvz48qiwntyx88.png" /></div>
''',
      );

      expect(result.imageUrls, hasLength(2));
      expect(result.episodeLinks.map((link) => link.url).toList(), <String>[
        'https://bbs.yamibo.com/thread-527284-1-1.html',
        'https://bbs.yamibo.com/thread-527285-1-1.html',
        'https://bbs.yamibo.com/thread-527287-1-1.html',
        'https://bbs.yamibo.com/thread-527288-1-1.html',
      ]);
      expect(result.episodeLinks.first.episodeTitle, '16话后篇');
    });

    test('parses dense chapter list with mixed legacy highlight links', () {
      final parser = HtmlComicParserService();
      final result = parser.parse(
        message: '''
<a href="https://bbs.yamibo.com/thread-528734-1-1.html">第01话</a>
<a href="https://bbs.yamibo.com/thread-529668-1-1.html">第02话</a>
<a href="https://bbs.yamibo.com/thread-530370-1-1.html">第03话</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=533386&amp;amp;highlight=%BC%AB%CF%DEOL%CF%EB%D2%AA%B7%FE%CA%CC%B7%B4%C5%C9%C7%A7%BD%F0%B4%F3%D0%A1%BD%E3">第01卷番外</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;amp;tid=550267&amp;amp;highlight=%E6%9E%81%E9%99%90OL">第22话</a>
<a href="https://bbs.yamibo.com/thread-569740-1-1.html">第36话</a>
<div class="img"><img src="https://bbs.yamibo.com/data/attachment/forum/202606/10/201004y9mlrlmmzyuikck4.jpg" /></div>
''',
      );

      expect(result.episodeLinks.map((link) => link.url).toList(), <String>[
        'https://bbs.yamibo.com/thread-528734-1-1.html',
        'https://bbs.yamibo.com/thread-529668-1-1.html',
        'https://bbs.yamibo.com/thread-530370-1-1.html',
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=533386',
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=550267',
        'https://bbs.yamibo.com/thread-569740-1-1.html',
      ]);
      expect(
        result.episodeLinks
            .where((link) => link.url.contains('tid=533386'))
            .single
            .url,
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=533386',
      );
      expect(result.imageUrls, hasLength(1));
    });

    test('keeps image-only single thread comic parseable', () {
      final parser = HtmlComicParserService();
      final result = parser.parse(
        message: '''
<div class="img"><img src="https://bbs.yamibo.com/data/attachment/forum/202606/10/page1.jpg" /></div>
<div class="img"><img src="https://bbs.yamibo.com/data/attachment/forum/202606/10/page2.jpg" /></div>
''',
      );

      expect(result.imageUrls, hasLength(2));
      expect(result.episodeLinks, isEmpty);
    });

    test('supports damaged href with leading semicolon tid form', () {
      final parser = HtmlComicParserService();
      final result = parser.parse(
        message:
            '<a href=";tid=537155&amp;highlight=%E5%B9%B3%E8%89%AF%E6%B7%B1">04</a>',
      );

      expect(result.episodeLinks.length, 1);
      expect(
        result.episodeLinks.single.url,
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=537155',
      );
      expect(result.episodeLinks.single.episodeTitle, '04');
    });

    test('captures parsing debug signals for observability', () {
      final parser = HtmlComicParserService();
      final result = parser.parse(
        message: '''
<img src="https://img.test/a.jpg" />
<a href="thread-101-1-1.html">01</a>
<a href="https://bbs.yamibo.com/thread-200-1-1.html">\u76ee\u5f55</a>
''',
      );

      final debug = result.parsingDebug;
      expect(debug, isNotNull);
      expect(debug!.totalAnchors, 2);
      expect(debug.totalEpisodeLinks, 2);
      expect(debug.signals.isNotEmpty, true);
      expect(debug.signals.any((s) => s.message.contains('catalog hit')), true);
    });

    test(
      'parseInput merges DOM and attachment images with stable deduplication',
      () {
        final parser = HtmlComicParserService();
        final result = parser.parseInput(
          const ComicPostParseInput(
            messageHtml: '''
<img src="https://img.test/dom-1.jpg" />
<img src="https://img.test/shared.jpg" />
''',
            attachmentImageUrls: <String>[
              'https://img.test/shared.jpg',
              'https://bbs.yamibo.com/data/attachment/forum/201802/16/attachment.jpg',
            ],
          ),
        );

        expect(result.imageUrls, <String>[
          'https://img.test/dom-1.jpg',
          'https://img.test/shared.jpg',
          'https://bbs.yamibo.com/data/attachment/forum/201802/16/attachment.jpg',
        ]);
        expect(
          result.parsingDebug!.signals.any(
            (signal) => signal.message == 'attachment images=2',
          ),
          isTrue,
        );
      },
    );

    test('extracts desktop attachment-form comic pages after detail parsing', () {
      const detailParser = ThreadDetailHtmlParser();
      final html = File('docs/html/帖子详细页/附件形式的漫画帖.html').readAsStringSync();
      final detail = detailParser.parse(
        html,
        fallbackTid: '572699',
        fallbackPage: 1,
      );

      final parser = HtmlComicParserService();
      final result = parser.parse(message: detail.posts.first.message);

      expect(result.imageUrls, hasLength(75));
      expect(
        result.imageUrls.first,
        'https://bbs.yamibo.com/data/attachment/forum/202606/20/132204m50yzddi08r50cyd.png',
      );
      expect(
        result.imageUrls.last,
        'https://bbs.yamibo.com/data/attachment/forum/202606/20/132245ea1y0rwiv1y1o00i.png',
      );
    });
  });
}
