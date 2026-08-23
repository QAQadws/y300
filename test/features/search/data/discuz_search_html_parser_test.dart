import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/search/data/services/discuz_search_html_parser.dart';
import 'package:y300/features/search/domain/models/forum_search_models.dart';

void main() {
  test(
    'DiscuzSearchHtmlParser parses strict result roots and continuation',
    () {
      final parser = const DiscuzSearchHtmlParser();
      final result = parser.parse(
        html: '''
<ul class="threadlist">
  <li class="list">
    <a href="forum.php?mod=viewthread&amp;tid=570616&amp;mobile=2">
      <div class="threadlist_tit cl"><em>标题A</em></div>
    </a>
    <div class="threadlist_foot cl">
      <ul><li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;mobile=2">漫画区</a></li></ul>
    </div>
  </li>
</ul>
<div class="pg">
  <a href="search.php?mod=forum&amp;searchid=15063&amp;page=2&amp;mobile=2" class="nxt">下一页</a>
</div>
''',
        pageUri: Uri.parse(
          'https://bbs.yamibo.com/search.php?mod=forum&searchid=15063&mobile=2',
        ),
        query: const ForumSearchQuery(keyword: '标题'),
        requestedPage: 1,
        expectedSearchContextId: '15063',
      );

      expect(result.topics, hasLength(1));
      expect(result.topics.single.tid, '570616');
      expect(result.topics.single.forumId, '30');
      expect(result.topics.single.title, '标题A');
      expect(result.currentPage, 1);
      expect(result.nextPageUri?.queryParameters['page'], '2');
    },
  );

  test('DiscuzSearchHtmlParser treats an empty threadlist as success', () {
    final result = const DiscuzSearchHtmlParser().parse(
      html: '<ul class="threadlist"></ul>',
      pageUri: Uri.parse(
        'https://bbs.yamibo.com/search.php?mod=forum&searchid=15063',
      ),
      query: const ForumSearchQuery(keyword: 'empty'),
      requestedPage: 1,
      expectedSearchContextId: '15063',
    );

    expect(result.topics, isEmpty);
    expect(result.nextPageUri, isNull);
  });

  test('DiscuzSearchHtmlParser fails when the required root is missing', () {
    expect(
      () => const DiscuzSearchHtmlParser().parse(
        html: '<ul class="other-list"></ul>',
        pageUri: Uri.parse(
          'https://bbs.yamibo.com/search.php?mod=forum&searchid=15063',
        ),
        query: const ForumSearchQuery(keyword: 'missing'),
        requestedPage: 1,
        expectedSearchContextId: '15063',
      ),
      throwsA(
        isA<DiscuzSearchHtmlParseException>().having(
          (error) => error.code,
          'code',
          'search_root_missing',
        ),
      ),
    );
  });
}
