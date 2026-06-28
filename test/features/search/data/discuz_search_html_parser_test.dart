import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/search/data/services/discuz_search_html_parser.dart';

void main() {
  test('DiscuzSearchHtmlParser parses list items and next page link', () {
    final parser = DiscuzSearchHtmlParser();
    final result = parser.parse('''
<li class="list">
  <a href="forum.php?mod=viewthread&amp;tid=570616&amp;mobile=2">
    <div class="threadlist_tit cl"><em>标题A</em></div>
  </a>
  <div class="threadlist_foot cl">
    <ul><li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></li></ul>
  </div>
</li>
<div class="pg">
  <a href="search.php?mod=forum&amp;searchid=15063&amp;page=3&amp;mobile=2" class="nxt">下一页</a>
</div>
''');

    expect(result.items.length, 1);
    expect(result.items.first.tid, '570616');
    expect(result.items.first.fid, '30');
    expect(result.items.first.title, '标题A');
    expect(result.nextPageUrl, contains('search.php?mod=forum&searchid=15063&page=3&mobile=2'));
  });
}
