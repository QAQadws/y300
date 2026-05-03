import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/catalog_thread_html_parser.dart';

void main() {
  group('CatalogThreadHtmlParser', () {
    test('extracts thread tid and subject from table rows and deduplicates', () {
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
    });

    test('parses next page url from nxt class anchor', () {
      final parser = CatalogThreadHtmlParser();
      final result = parser.parse(
        pageUrl: 'https://bbs.yamibo.com/misc.php?mod=tag&id=20452&type=thread&page=1',
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
  });
}

