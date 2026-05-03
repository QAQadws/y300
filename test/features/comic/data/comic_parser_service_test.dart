import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

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
      expect(result.episodeLinks.first.url, 'https://bbs.yamibo.com/thread-100-1-1.html');
      expect(result.episodeLinks.first.episodeTitle, '1');
      expect(result.catalogUrl, 'https://bbs.yamibo.com/thread-200-1-1.html');
      expect(result.inferredAuthor, '\u6d4b\u8bd5\u7ec4');
      expect(result.plainTextSummary, contains('\u4f5c\u8005: \u6d4b\u8bd5\u7ec4'));
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
      expect(result.episodeLinks.first.url, 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=530646');
      expect(result.episodeLinks.first.episodeTitle, '01');
      expect(
        result.episodeLinks.where((e) => e.rawText == '\u7b2c\u4e09\u5377\u7279\u5178').single.url,
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=554347&fromuid=360078',
      );
    });

    test('supports damaged href with leading semicolon tid form', () {
      final parser = HtmlComicParserService();
      final result = parser.parse(
        message: '<a href=";tid=537155&amp;highlight=%E5%B9%B3%E8%89%AF%E6%B7%B1">04</a>',
      );

      expect(result.episodeLinks.length, 1);
      expect(result.episodeLinks.single.url, 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=537155');
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
      expect(
        debug.signals.any((s) => s.message.contains('catalog hit')),
        true,
      );
    });
  });
}
