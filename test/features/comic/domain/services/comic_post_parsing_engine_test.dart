import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';

void main() {
  group('ComicPostParsingEngine', () {
    test('extracts thread/viewthread/damaged tid links and deduplicates by tid', () {
      final engine = ComicPostParsingEngine();
      final result = engine.parse(
        messageHtml: '''
<a href=";tid=537155&amp;highlight=abc">04</a>
<a href="https://bbs.yamibo.com/thread-544245-1-1.html">09</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=537155&amp;fromuid=360078">第1话</a>
''',
      );

      expect(result.episodes.length, 2);
      expect(result.episodes.any((e) => e.tid == '537155'), true);
      expect(result.episodes.any((e) => e.tid == '544245'), true);
    });

    test('marks catalog links when anchor text contains 目录', () {
      final engine = ComicPostParsingEngine();
      final result = engine.parse(
        messageHtml: '<a href="https://bbs.yamibo.com/misc.php?mod=tag&id=21137">目录</a>',
      );

      expect(result.catalogLinks.length, 1);
      expect(result.catalogLinks.first, 'https://bbs.yamibo.com/misc.php?mod=tag&id=21137');
    });

    test('marks Yamibo tag elevator links as catalog links', () {
      final engine = ComicPostParsingEngine();
      final result = engine.parse(
        messageHtml: '<a href="https://bbs.yamibo.com/misc.php?mod=tag&amp;amp;id=18235">電梯</a>',
      );

      expect(result.catalogLinks, <String>['https://bbs.yamibo.com/misc.php?mod=tag&id=18235']);
    });

    test('cluster rule promotes sequential numeric links', () {
      final engine = ComicPostParsingEngine();
      final result = engine.parse(
        messageHtml: '''
<a href="thread-100-1-1.html">01</a>
<a href="thread-101-1-1.html">02</a>
<a href="thread-102-1-1.html">03</a>
''',
      );

      expect(result.episodes.length, 3);
      expect(result.episodes.every((e) => e.groupId != null), true);
    });

    test('preserves message order so specials stay interleaved between episodes', () {
      final engine = ComicPostParsingEngine();
      final result = engine.parse(
        messageHtml: '''
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=530646">01</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=533029">02</a>
<a href="https://bbs.yamibo.com/thread-544320-1-1.html">第一卷特典</a>
<a href="https://bbs.yamibo.com/thread-545243-1-1.html">10</a>
<a href="https://bbs.yamibo.com/thread-546003-1-1.html">13</a>
<a href="https://bbs.yamibo.com/thread-546436-1-1.html">第二卷特典</a>
<a href="https://bbs.yamibo.com/thread-546513-1-1.html">14</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=554347&amp;fromuid=360078">第三卷特典</a>
<a href="https://bbs.yamibo.com/thread-554377-1-1.html">19</a>
''',
      );

      expect(
        result.episodes.map((e) => e.titleRaw).toList(),
        <String>['01', '02', '第一卷特典', '10', '13', '第二卷特典', '14', '第三卷特典', '19'],
      );
    });
  });
}
