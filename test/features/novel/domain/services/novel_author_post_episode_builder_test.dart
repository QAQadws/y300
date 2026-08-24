import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/services/novel_author_post_episode_builder.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../test_support/novel_title_fixtures.dart';

void main() {
  const builder = DefaultNovelAuthorPostEpisodeBuilder();

  test('rejects posts whose local author identity does not match', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(authorId: '999', message: '<p>不应导入。</p>'),
      authorFilteredPage: 1,
      orderIndex: 0,
    );

    expect(draft, isNull);
  });

  test('skips a first post that only contains intro and catalog metadata', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        isFirst: true,
        number: 1,
        message: '''
          <p>简介</p><p>这只是作品简介。</p><p>目录</p>
          <strong>作品分卷标题</strong><br>
          <p><a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=2">第一章</a></p>
        ''',
      ),
      authorFilteredPage: 1,
      orderIndex: 0,
    );

    expect(draft, isNull);
  });

  test(
    'ignores Discuz collapse controls when checking a catalog-only first post',
    () {
      final draft = builder.build(
        novelId: 'novel:55:565218',
        tid: '565218',
        publisherId: '406769',
        post: _post(
          isFirst: true,
          number: 1,
          message: '''
          <i class="pstatus">本帖最后由 作者 于 2026-7-6 23:25 编辑</i>
          <p>简介</p><p>作品简介。</p><p>目录：</p>
          <div class="showcollapse_box">
            <div class="showcollapse_title">ACT01-20</div>
            <div class="showcollapse_content">
              <a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=41425060">ACT01</a>
              <div class="showcollapse_gather">收起</div>
            </div>
          </div>
        ''',
        ),
        authorFilteredPage: 1,
        orderIndex: 0,
      );

      expect(draft, isNull);
    },
  );

  test(
    'uses the first preface line before metadata for a first-post title',
    () {
      final draft = builder.build(
        novelId: 'novel:55:565218',
        tid: '565218',
        publisherId: '406769',
        post: _post(
          isFirst: true,
          number: 1,
          message: '''
          <strong>我的朋友毫不踌躇</strong><br>
          <strong>原文标题：わたしの友達は躊躇わない</strong><br>
          <strong>简介</strong><br>
          作品简介。<br>
          <strong>目录：</strong><br>
          <div class="showcollapse_box showcollapse_active">
            <div class="showcollapse_title">ACT101-120</div>
            <div class="showcollapse_content">
              <a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=41577032">ACT112</a><br>
              ACT112.8<br>
              ACT113
              <div class="showcollapse_gather">收起</div>
            </div>
          </div>
        ''',
        ),
        authorFilteredPage: 1,
        orderIndex: 0,
      );

      expect(draft?.episodeTitle, '我的朋友毫不踌躇');
    },
  );

  test(
    'uses prose after a collapse control without rewriting chapter HTML',
    () {
      final draft = builder.build(
        novelId: 'novel:55:565218',
        tid: '565218',
        publisherId: '406769',
        post: _post(
          pid: '41425060',
          number: 2,
          message: '''
          <div class="showcollapse_gather">收起</div>
          <p>ACT01 我的朋友毫不踌躇</p>
          <p>真正的章节正文。</p>
        ''',
        ),
        authorFilteredPage: 1,
        orderIndex: 0,
      );

      expect(draft?.episodeTitle, 'ACT01 我的朋友毫不踌躇');
      expect(draft?.rawHtml, contains('showcollapse_gather'));
      expect(draft?.rawHtml, contains('收起'));
    },
  );

  test('builds stable episode data from a publisher post', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '40213902',
        number: 2,
        message: '<p>雨终于停了。她推开窗。</p><p>第二段正文</p>',
      ),
      authorFilteredPage: 3,
      orderIndex: 7,
    );

    expect(draft, isNotNull);
    expect(draft?.episodeId, 'novel:55:521519:40213902');
    expect(draft?.sourceTid, '521519');
    expect(draft?.sourcePid, '40213902');
    expect(draft?.sourcePage, 3);
    expect(draft?.orderIndex, 7);
    expect(draft?.episodeTitle, '雨终于停了。');
    expect(draft?.plainText, contains('第二段正文'));
    expect(draft?.paragraphs, contains('第二段正文'));
  });

  test('uses leading inline heading text before the first body div', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '41554030',
        number: 2,
        message: '''
          <strong><strong><font face="&amp;quot">喜歡的人和義妹</font></strong></strong><br>
          <strong><font face="&amp;quot">第一話（１）</font></strong>
          <div align="left">　　</div>
          <div align="left">　　如果能轉世重生的話，我想成為像她那樣的人。</div>
        ''',
      ),
      authorFilteredPage: 1,
      orderIndex: 0,
    );

    expect(draft?.episodeTitle, '喜歡的人和義妹');
  });

  test('skips a publisher floor that replies with a Discuz quote', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '40213904',
        number: 5,
        message: '''
          <div class="quote"><blockquote>
            <font color="#999999">purplewind 发表于 2025-5-4 16:58</font><br>
            啊这，怎么开局车祸啊，推进姐妹关系有点太强硬了吧hhhh
          </blockquote></div>
          <br>而且还是无自觉的随时随地不看场合秀恩爱（x
        ''',
      ),
      authorFilteredPage: 1,
      orderIndex: 4,
    );

    expect(draft, isNull);
  });

  test('skips an attributed blockquote reply without its wrapper class', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '40213907',
        number: 8,
        message: '''
          <blockquote>hiyade 发表于 2025-12-16 21:29<br>被引用内容</blockquote>
          <p>楼主的回复。</p>
        ''',
      ),
      authorFilteredPage: 1,
      orderIndex: 7,
    );

    expect(draft, isNull);
  });

  test('does not reject an unattributed literary blockquote', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '40213909',
        number: 10,
        message: '''
          <blockquote>故事中的题记，不是论坛回复。</blockquote>
          <p>章节正文从这里开始。</p>
        ''',
      ),
      authorFilteredPage: 1,
      orderIndex: 9,
    );

    expect(draft?.episodeTitle, '章节正文从这里开始。');
  });

  test('strips Discuz edit notices without discarding adjacent prose', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '40213905',
        number: 6,
        message: '''
          <i class="pstatus">本帖最后由 咕哒子鸭 于 2025-5-4 19:36 编辑</i>
          <p>真正的章节正文。</p>
          <p>本帖最后由 另一位作者 于2025-5-419:36编辑粘连后的正文。</p>
        ''',
      ),
      authorFilteredPage: 1,
      orderIndex: 5,
    );

    expect(draft?.episodeTitle, '真正的章节正文。');
    expect(draft?.plainText, contains('本帖最后由 咕哒子鸭'));
  });

  test('uses prose attached to an unmarked edit notice', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '40213906',
        number: 7,
        message: '<p>本帖最后由 咕哒子鸭 于2025-5-419:36编辑正文从这里开始。后一句。</p>',
      ),
      authorFilteredPage: 1,
      orderIndex: 6,
    );

    expect(draft?.episodeTitle, '正文从这里开始。');
  });

  test('uses the first prose block after pstatus as the chapter title', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '40213908',
        number: 9,
        message: '''
          <div class="message">
            <i class="pstatus"> 本帖最后由 没有太阳的晴日 于 2026-2-24 13:58 编辑 </i><br><br>
            <div align="center"><font face="宋体"><font size="5">ACT05　知道别人穿什么胖次究竟想干嘛？</font></font></div>
            <div align="left"><font face="Arial"><font size="3">「嗯？」</font></font></div>
          </div>
        ''',
      ),
      authorFilteredPage: 1,
      orderIndex: 8,
    );

    expect(draft?.episodeTitle, 'ACT05 知道别人穿什么胖次究竟想干嘛？');
  });

  test('preserves a decimal ACT number in the first prose heading', () {
    final fixture = novelChapterTitleFixtures.singleWhere(
      (item) => item.id == 'decimal-act-number-after-edit-notice',
    );
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(pid: '41569751', number: 13, message: fixture.rawHtml),
      authorFilteredPage: 1,
      orderIndex: 12,
    );

    expect(draft?.episodeTitle, fixture.expectedTitle);
  });

  test('expands verified attach placeholders and accepts image-only posts', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '40213903',
        number: 3,
        message: '[attach]88[/attach]',
        attachments: const <ForumPostAttachmentImage>[
          ForumPostAttachmentImage(
            aid: '88',
            url: 'https://bbs.yamibo.com/',
            attachment: 'data/attachment/forum/cover.jpg',
            filename: 'cover.jpg',
            attachimg: '1',
            ext: 'jpg',
          ),
        ],
      ),
      authorFilteredPage: 1,
      orderIndex: 2,
    );

    expect(draft, isNotNull);
    // The domain keeps a stable source-TID sentinel; the presentation resolver
    // turns it into the localized fallback title.
    expect(draft?.episodeTitle, '521519');
    expect(draft?.rawHtml, contains('<img src='));
    expect(draft?.imageUrls, hasLength(1));
  });
}

ThreadPost _post({
  String pid = '40213901',
  String authorId = '406769',
  String message = '',
  int number = 1,
  bool isFirst = false,
  List<ForumPostAttachmentImage> attachments =
      const <ForumPostAttachmentImage>[],
}) {
  return ThreadPost(
    pid: pid,
    author: 'INCSKY16',
    authorId: authorId,
    message: message,
    number: number,
    isFirst: isFirst,
    dateline: '2026-07-13',
    attachmentImages: attachments,
  );
}
