import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/tags/data/services/discuz_tag_directory_html_parser.dart';

void main() {
  const pageUrl =
      'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1';
  const parser = DiscuzTagDirectoryHtmlParser();

  test('maps the desktop fixture in DOM order', () {
    final html = File('docs/html/帖子详细页/tag页样例.html').readAsStringSync();
    final data = parser.parse(
      html: html,
      pageUrl: pageUrl,
      expectedTagId: '21920',
      requestedPage: 1,
    );

    expect(data.tag.id, '21920');
    expect(data.tag.name, 'きさらぎ壱吾短篇集');
    expect(data.topics, hasLength(9));
    expect(data.topics.map((topic) => topic.tid).toList(), [
      '572514',
      '572515',
      '572543',
      '572575',
      '572576',
      '572612',
      '572613',
      '572661',
      '572711',
    ]);
    expect(data.topics.first.title, '【个人汉化】[きさらぎ壱吾]晒猫');
    expect(data.topics.first.replyCount, 14);
    expect(data.topics.first.viewCount, 3092);
    expect(data.topics.first.hasImageAttachment, isTrue);
    expect(data.pagination.currentPage, 1);
    expect(data.pagination.totalPages, isNull);
    expect(data.pagination.hasNext, isNull);
  });

  test('accepts an explicit empty directory but rejects a missing root', () {
    const empty = '''
      <div id="pt"><a href="misc.php?mod=tag&amp;id=21920">tag</a></div>
      <div class="bm tl"><div class="bm_c"><table></table></div></div>
    ''';
    final data = parser.parse(
      html: empty,
      pageUrl: pageUrl,
      expectedTagId: '21920',
      requestedPage: 1,
    );
    expect(data.topics, isEmpty);

    expect(
      () => parser.parse(
        html:
            '<div id="pt"><a href="misc.php?mod=tag&amp;id=21920">tag</a></div>',
        pageUrl: pageUrl,
        expectedTagId: '21920',
        requestedPage: 1,
      ),
      throwsFormatException,
    );
  });

  test('fails closed for tag identity, topic identity and invalid counts', () {
    const base = '''
      <div id="pt"><a href="misc.php?mod=tag&amp;id=21920">tag</a></div>
      <div class="bm tl"><table><tr>
        <th><a href="thread-1-1-1.html">Topic</a></th>
        <td></td><td></td><td></td>
        <td class="num"><a href="thread-1-1-1.html">bad</a><em>2</em></td>
      </tr></table></div>
    ''';
    expect(
      () => parser.parse(
        html: base,
        pageUrl: pageUrl,
        expectedTagId: '21920',
        requestedPage: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => parser.parse(
        html: base.replaceAll('id=21920', 'id=99'),
        pageUrl: pageUrl,
        expectedTagId: '21920',
        requestedPage: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => parser.parse(
        html: base.replaceFirst('thread-1-1-1.html', 'thread--1-1.html'),
        pageUrl: pageUrl,
        expectedTagId: '21920',
        requestedPage: 1,
      ),
      throwsFormatException,
    );
  });

  test(
    'keeps missing optional values nullable and parses directional pages',
    () {
      const html = '''
      <div id="pt"><a href="misc.php?mod=tag&amp;id=21920">tag</a></div>
      <div class="bm tl"><table><tr>
        <th><a href="thread-1-1-1.html">Topic</a></th>
        <td class="by"></td><td class="by"></td><td class="num"></td><td class="by"></td>
      </tr></table></div>
      <div class="pg">
        <a class="prev" href="misc.php?mod=tag&amp;id=21920&amp;type=thread&amp;page=1">上一页</a>
        <strong>2</strong>
        <a class="nxt" href="misc.php?mod=tag&amp;id=21920&amp;type=thread&amp;page=3">下一页</a>
      </div>
      <div class="ptm"><a href="misc.php?mod=tag&amp;id=21920&amp;type=thread">更多...</a></div>
    ''';
      final data = parser.parse(
        html: html,
        pageUrl: pageUrl,
        expectedTagId: '21920',
        requestedPage: 2,
      );
      final topic = data.topics.single;
      expect(topic.forumName, isNull);
      expect(topic.replyCount, isNull);
      expect(topic.hasAttachment, isNull);
      expect(data.pagination.currentPage, 2);
      expect(data.pagination.hasPrevious, isTrue);
      expect(data.pagination.hasNext, isTrue);
    },
  );

  test('rejects empty titles and duplicate topic identities', () {
    const emptyTitle = '''
      <div id="pt"><a href="misc.php?mod=tag&amp;id=21920">tag</a></div>
      <div class="bm tl"><table><tr><th><a href="thread-1-1-1.html"></a></th>
        <td></td><td></td><td></td><td></td>
      </tr></table></div>
    ''';
    expect(
      () => parser.parse(
        html: emptyTitle,
        pageUrl: pageUrl,
        expectedTagId: '21920',
        requestedPage: 1,
      ),
      throwsFormatException,
    );

    const duplicate = '''
      <div id="pt"><a href="misc.php?mod=tag&amp;id=21920">tag</a></div>
      <div class="bm tl"><table>
        <tr><th><a href="thread-1-1-1.html">one</a></th><td></td><td></td><td></td><td></td></tr>
        <tr><th><a href="thread-1-1-1.html">duplicate</a></th><td></td><td></td><td></td><td></td></tr>
      </table></div>
    ''';
    expect(
      () => parser.parse(
        html: duplicate,
        pageUrl: pageUrl,
        expectedTagId: '21920',
        requestedPage: 1,
      ),
      throwsFormatException,
    );
  });

  test(
    'reports verified total page counts without guessing from row count',
    () {
      const html = '''
      <div id="pt"><a href="misc.php?mod=tag&amp;id=21920">tag</a></div>
      <div class="bm tl"><table><tr><th><a href="thread-1-1-1.html">one</a></th>
        <td></td><td></td><td></td><td></td>
      </tr></table></div>
      <div class="pg"><strong>2</strong><label><span title="共 4 页">2/4 页</span></label></div>
    ''';
      final data = parser.parse(
        html: html,
        pageUrl: pageUrl,
        expectedTagId: '21920',
        requestedPage: 2,
      );
      expect(data.pagination.totalPages, 4);
      expect(data.pagination.hasPrevious, isTrue);
      expect(data.pagination.hasNext, isTrue);
    },
  );
}
