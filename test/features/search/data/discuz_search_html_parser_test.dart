import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/search/data/discuz_search_html_parser.dart';

void main() {
  test('DiscuzSearchHtmlParser parses list items with tid/fid/title', () {
    final parser = DiscuzSearchHtmlParser();
    final result = parser.parse('''
<li class="list">
  <div class="threadlist_top cl">
    <div class="muser">
      <h3><a class="mmc">朔月霏</a></h3>
      <span class="mtime">2026-5-2 23:20</span>
    </div>
  </div>
  <a href="forum.php?mod=viewthread&amp;tid=570616&amp;extra=&amp;mobile=2">
    <div class="threadlist_tit cl"><em>【提黄灯喵汉化组】百合情结 14</em></div>
  </a>
  <div class="threadlist_foot cl">
    <ul><li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">#中文百合漫画区</a></li></ul>
  </div>
</li>
''');

    expect(result.items.length, 1);
    expect(result.items.first.tid, '570616');
    expect(result.items.first.fid, '30');
    expect(result.items.first.title, contains('百合情结 14'));
  });
}

