import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/catalog_thread_html_parser.dart';

void main() {
  group('CatalogThreadHtmlParser', () {
    test(
      'extracts thread tid and subject from table rows and deduplicates',
      () {
        final parser = CatalogThreadHtmlParser();
        final result = parser.parse(
          pageUrl: 'https://bbs.yamibo.com/misc.php?mod=tag&id=21137',
          html: '''
<div class="bm_c">
<table cellspacing="0" cellpadding="0"><tr>
<td class="icn"><a href="thread-558227-1-1.html"><i></i></a></td>
<th><a href="thread-558227-1-1.html" target="_blank">【萌木汉化组】献予你的支配之礼 第1.1话</a></th>
<td class="num"><a href="thread-558227-1-1.html" class="xi2">10</a></td>
</tr>
<tr>
<td class="icn"><a href="thread-558976-1-1.html"><i></i></a></td>
<th><a href="thread-558976-1-1.html" target="_blank">【萌木汉化组】献予你的支配之礼 第2话</a></th>
<td class="num"><a href="thread-558976-1-1.html" class="xi2">7</a></td>
</tr></table>
</div>
''',
        );

        expect(result.entries.length, 2);
        expect(result.entries[0].tid, '558227');
        expect(result.entries[0].subject.contains('第1.1话'), isTrue);
        expect(result.entries[1].tid, '558976');
      },
    );

    test('parses next page url from nxt class anchor', () {
      final parser = CatalogThreadHtmlParser();
      final result = parser.parse(
        pageUrl:
            'https://bbs.yamibo.com/misc.php?mod=tag&id=20452&type=thread&page=1',
        html: '''
<html><body>
<a class="nxt" href="misc.php?mod=tag&id=20452&type=thread&page=2">下一页</a>
</body></html>
''',
      );

      expect(
        result.nextPageUrl,
        'https://bbs.yamibo.com/misc.php?mod=tag&id=20452&type=thread&page=2',
      );
    });

    test('falls back to page-wide anchors when tag page has no table rows', () {
      final parser = CatalogThreadHtmlParser();
      final result = parser.parse(
        pageUrl:
            'https://bbs.yamibo.com/misc.php?mod=tag&id=18235&type=thread&page=1',
        html: '''
<html><body>
<ul class="thread-list">
<li><a href="thread-501-1-1.html">好事多磨 第1话</a></li>
<li><a href="forum.php?mod=viewthread&amp;tid=502">好事多磨 第2话</a></li>
</ul>
</body></html>
''',
      );

      expect(result.entries.map((entry) => entry.tid), <String>['501', '502']);
      expect(result.entries[1].subject, '好事多磨 第2话');
    });

    test('rejects utility links and url-looking thread labels', () {
      final parser = CatalogThreadHtmlParser();
      final result = parser.parse(
        pageUrl: 'https://bbs.yamibo.com/misc.php?mod=tag&id=20686',
        html: '''
<table>
<tr><th>
<a href="forum.php?mod=viewthread&amp;tid=475263">https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=475263&amp;fromuid=691344</a>
<a href="misc.php?mod=misc&amp;action=viewratings&amp;tid=475263">参与人数 9</a>
</th></tr>
<tr><th>
<a href="forum.php?mod=viewthread&amp;tid=475264">正确章节 第2话</a>
</th></tr>
</table>
''',
      );

      expect(result.entries, hasLength(1));
      expect(result.entries.single.tid, '475264');
      expect(result.entries.single.subject, '正确章节 第2话');
    });

    test('extracts current and total pages from pagination block', () {
      final parser = CatalogThreadHtmlParser();
      final result = parser.parse(
        pageUrl:
            'https://bbs.yamibo.com/misc.php?mod=tag&id=21146&type=thread&page=1',
        html: '''
<div class="pgs mtm cl"><div class="pg">
<strong>1</strong>
<a href="misc.php?mod=tag&id=21146&type=thread&amp;page=2">2</a>
<a href="misc.php?mod=tag&id=21146&type=thread&amp;page=3">3</a>
<label><input type="text" name="custompage" class="px" size="2" value="1" />
<span title="共 3 页"> / 3 页</span></label>
<a href="misc.php?mod=tag&id=21146&type=thread&amp;page=2" class="nxt">下一页</a>
</div></div>
''',
      );

      expect(result.currentPage, 1);
      expect(result.totalPages, 3);
      expect(
        result.nextPageUrl,
        'https://bbs.yamibo.com/misc.php?mod=tag&id=21146&type=thread&page=2',
      );
    });
  });
}
