import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/thread/data/services/thread_detail_html_parser.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

void main() {
  group('ThreadDetailHtmlParser', () {
    const parser = ThreadDetailHtmlParser();

    test(
      'parses desktop single-choice poll thread into mobile detail data',
      () {
        final html = File('docs/html/帖子详细页/一个电脑端单选帖.html').readAsStringSync();

        final result = parser.parse(
          html,
          fallbackTid: '572529',
          fallbackPage: 1,
        );

        expect(result.tid, '572529');
        expect(result.fid, '33');
        expect(result.typeid, '410');
        expect(result.typeName, '理性探讨');
        expect(result.forumName, '海域區');
        expect(result.forumUrl, contains('forum-33-1.html'));
        expect(result.subject, '突发奇想，调查一下大家对于两种百合形态的偏好');
        expect(result.views, 937);
        expect(result.replies, 67);
        expect(result.currentPage, 1);
        expect(result.lastPage, 4);
        expect(result.nextPageUrl, contains('thread-572529-2-1.html'));
        expect(result.reverseOrderUrl, contains('ordertype=1'));
        expect(result.onlyAuthorUrl, contains('authorid=448216'));
        expect(result.favoriteUrl, contains('ac=favorite'));
        expect(result.shareUrl, contains('ac=share'));
        expect(result.homeUrl, 'https://bbs.yamibo.com/index.php');
        expect(result.desktopUrl, contains('mod=viewthread'));
        expect(result.posts.length, greaterThan(10));

        final firstPost = result.posts.first;
        expect(firstPost.pid, '41562047');
        expect(firstPost.author, 'GuGu_');
        expect(firstPost.authorId, '448216');
        expect(firstPost.number, 1);
        expect(firstPost.isFirst, isTrue);
        expect(firstPost.dateline, '2026-6-16 01:16');
        expect(firstPost.avatarUrl, contains('000/44/82/16_avatar_middle.jpg'));
        expect(firstPost.message, contains('我喜欢的你恰好是女性'));
        expect(firstPost.rateUrl, contains('action=rate'));
        expect(firstPost.commentUrl, contains('action=comment'));
        expect(firstPost.commentUrl, contains('tid=572529'));
        expect(firstPost.commentUrl, contains('pid=41562047'));
        expect(firstPost.replyUrl, contains('action=reply'));
        expect(firstPost.rateSummary, contains('参与人数'));
        expect(firstPost.ratingSummary?.participantText, '参与人数 1');
        expect(firstPost.ratingSummary?.scoreText, '积分 +2');
        expect(firstPost.ratingSummary?.viewAllUrl, contains('viewratings'));
        expect(firstPost.ratingSummary?.ratings.single.userName, '子子子车');
        expect(firstPost.ratingSummary?.ratings.single.userId, '736594');
        expect(firstPost.ratingSummary?.ratings.single.score, '+ 2');
        expect(firstPost.ratingSummary?.ratings.single.reason, '我很赞同');
        expect(
          firstPost.ratingSummary?.ratings.single.avatarUrl,
          contains('000/73/65/94_avatar_small.jpg'),
        );

        final poll = firstPost.poll!;
        expect(poll.isMultipleChoice, isFalse);
        expect(poll.summary, contains('单选投票'));
        expect(poll.deadlineText, contains('距结束还有'));
        expect(poll.actionUrl, contains('action=votepoll'));
        expect(poll.formHash, 'cba80c43');
        expect(poll.options.map((option) => option.label), [
          'A:我喜欢的你恰好是女性',
          'B:我喜欢作为女性的你',
        ]);
        expect(poll.options.first.percent, isNull);
      },
    );

    test('parses desktop multi-choice poll result bars', () {
      final html = File('docs/html/帖子详细页/一个电脑端多选帖.html').readAsStringSync();

      final result = parser.parse(html, fallbackTid: '572638', fallbackPage: 1);

      final poll = result.posts.first.poll!;
      expect(poll.isMultipleChoice, isTrue);
      expect(poll.maxChoices, 8);
      expect(poll.summary, contains('多选投票'));
      expect(poll.options.length, greaterThanOrEqualTo(5));
      expect(poll.options.first.label, '二次元类');
      expect(poll.options.first.percent, 19.28);
      expect(poll.options.first.voteCount, 43);
      expect(poll.options.first.colorHex, '#E92725');
    });

    test('parses already-voted desktop poll result without inputs', () {
      final result = parser.parse(
        _alreadyVotedPollThreadHtml,
        fallbackTid: '567764',
        fallbackPage: 1,
      );

      final poll = result.posts.first.poll!;
      expect(poll.isMultipleChoice, isTrue);
      expect(poll.maxChoices, 3);
      expect(poll.canVote, isFalse);
      expect(poll.statusText, contains('已经投过票'));
      expect(poll.options, hasLength(7));
      expect(poll.options.first.id, '1');
      expect(poll.options.first.label, '两个心灵靠近的过程');
      expect(poll.options.first.percent, 38.82);
      expect(poll.options.first.voteCount, 276);
      expect(poll.options.first.colorHex, '#E92725');
    });

    test(
      'parses desktop post comments with avatar author message and time',
      () {
        final html = File(
          'docs/html/帖子详细页/帖子中有帖子楼跳转链接.html',
        ).readAsStringSync();

        final result = parser.parse(
          html,
          fallbackTid: '572057',
          fallbackPage: 1,
        );

        final firstPost = result.posts.first;
        expect(firstPost.pid, '41554028');
        expect(firstPost.comments, hasLength(2));
        expect(firstPost.comments.first.author, '13549697590');
        expect(firstPost.comments.first.authorId, '601436');
        expect(
          firstPost.comments.first.avatarUrl,
          contains('000/60/14/36_avatar_small.jpg'),
        );
        expect(firstPost.comments.first.message, '爱看义妹系的有福了（比如我）');
        expect(firstPost.comments.first.dateline, '2026-6-12 12:12');
        expect(firstPost.comments.last.author, 'jingyuan3795');
        expect(firstPost.comments.last.message, '我说百合骨科是对的😋');

        final commentedReply = result.posts.firstWhere(
          (post) => post.pid == '41554366',
        );
        expect(commentedReply.comments.single.author, 'lztlzt');
        expect(commentedReply.comments.single.message, '那就标题就有点误导人了(☉｡☉)!');
        expect(commentedReply.comments.single.dateline, '2026-6-7 00:40');
      },
    );

    test('keeps desktop attachment image real urls for comic thread', () {
      final html = File('docs/html/帖子详细页/一个电脑端漫画帖子.html').readAsStringSync();

      final result = parser.parse(html, fallbackTid: '571955', fallbackPage: 1);

      expect(result.tid, '571955');
      expect(result.fid, '30');
      expect(result.forumName, '中文百合漫画区');
      expect(result.forumUrl, contains('forum-30-1.html'));
      expect(result.subject, contains('狱门抚子'));
      expect(result.views, 2426);
      expect(result.replies, 9);
      expect(result.posts, hasLength(greaterThanOrEqualTo(6)));

      final firstPost = result.posts.first;
      expect(firstPost.author, 'magtine');
      expect(
        firstPost.message,
        contains(
          'zoomfile="data/attachment/forum/202606/03/070117ka05z5dcpjl0prsp.jpg"',
        ),
      );
      expect(
        firstPost.message,
        contains(
          'src="data/attachment/forum/202606/03/070117ka05z5dcpjl0prsp.jpg"',
        ),
      );
      expect(
        firstPost.message,
        isNot(contains('src="static/image/common/none.gif"')),
      );
      expect(firstPost.poll, isNull);
    });

    test('parses attachment-form comic pages from desktop post container', () {
      final html = File('docs/html/帖子详细页/附件形式的漫画帖.html').readAsStringSync();

      final result = parser.parse(html, fallbackTid: '572699', fallbackPage: 1);

      expect(result.tid, '572699');
      expect(result.fid, '30');
      expect(result.typeid, '68');
      expect(result.typeName, '短篇漫畫');
      expect(result.subject, '【个人汉化】[浄土るる]由花緒renewal');
      expect(result.views, 623);
      expect(result.replies, 12);

      final firstPost = result.posts.first;
      expect(firstPost.pid, '41565305');
      expect(firstPost.author, 'Inchman');
      expect(firstPost.message, contains('宇宙生命体'));
      expect(
        firstPost.message,
        contains(
          'src="data/attachment/forum/202606/20/132204m50yzddi08r50cyd.png"',
        ),
      );
      expect(
        firstPost.message,
        contains(
          'src="data/attachment/forum/202606/20/132245ea1y0rwiv1y1o00i.png"',
        ),
      );
      expect(
        firstPost.message,
        isNot(contains('src="static/image/common/none.gif"')),
      );

      final sources = DefaultForumImageSourcePipeline.collectDomImageSources(
        firstPost.message,
        urlResolver: const SiteUrlResolver(),
        domAttributes: const <String>[
          'zoomfile',
          'file',
          'data-original',
          'data-src',
          'src',
        ],
      );
      expect(sources, hasLength(75));
      expect(
        sources.first.normalizedUrl,
        'https://bbs.yamibo.com/data/attachment/forum/202606/20/132204m50yzddi08r50cyd.png',
      );
      expect(
        sources.last.normalizedUrl,
        'https://bbs.yamibo.com/data/attachment/forum/202606/20/132245ea1y0rwiv1y1o00i.png',
      );
    });

    test('does not duplicate attachment gallery images already in message', () {
      final result = parser.parse(
        '''
        <html><body>
          <div id="postlist">
            <div id="post_1001">
              <td class="t_f" id="postmessage_1001">
                <p>正文</p>
                <img id="aimg_1" zoomfile="data/attachment/forum/page-1.jpg" src="static/image/common/none.gif">
                <img id="aimg_2" zoomfile="data/attachment/forum/page-2.jpg" src="static/image/common/none.gif">
              </td>
              <div class="attm">
                <img id="aimg_1" zoomfile="data/attachment/forum/page-1.jpg" src="static/image/common/none.gif">
                <img id="aimg_2" zoomfile="data/attachment/forum/page-2.jpg" src="static/image/common/none.gif">
              </div>
            </div>
          </div>
        </body></html>
        ''',
        fallbackTid: '100',
        fallbackPage: 1,
      );

      final message = result.posts.single.message;
      final fragment = html_parser.parseFragment(message);

      expect(fragment.querySelectorAll('img'), hasLength(2));
      expect(message, contains('data/attachment/forum/page-1.jpg'));
      expect(message, contains('data/attachment/forum/page-2.jpg'));
    });

    test('parses mobile comic thread with multiple inline attachment images', () {
      final html = File('docs/html/移动端html/漫画帖1.html').readAsStringSync();

      final result = parser.parse(html, fallbackTid: '573172', fallbackPage: 1);

      expect(result.tid, '573172');
      expect(result.fid, '30');
      expect(result.subject, '【雨月星系汉化】[ろんろ]关于耳洞的故事');
      expect(result.posts, isNotEmpty);

      final firstPost = result.posts.first;
      expect(firstPost.pid, '41574124');
      expect(firstPost.author, '懒得取名菌');
      expect(firstPost.message, contains('翻译：取名'));
      expect(
        firstPost.message,
        contains(
          'src="data/attachment/forum/202607/02/120322itw04wwgllu4t0ye.jpg"',
        ),
      );
      expect(
        firstPost.message,
        contains(
          'src="data/attachment/forum/202607/02/120329kr61q3oe6rw86ac1.png"',
        ),
      );
      expect(
        firstPost.message,
        isNot(contains('static/image/common/none.gif')),
      );

      final sources = DefaultForumImageSourcePipeline.collectDomImageSources(
        firstPost.message,
        urlResolver: const SiteUrlResolver(),
        domAttributes: const <String>[
          'zoomfile',
          'file',
          'data-original',
          'data-src',
          'src',
        ],
      );
      expect(sources, hasLength(8));
      expect(
        sources.first.normalizedUrl,
        'https://bbs.yamibo.com/data/attachment/forum/202607/02/120322itw04wwgllu4t0ye.jpg',
      );
      expect(
        sources.last.normalizedUrl,
        'https://bbs.yamibo.com/data/attachment/forum/202607/02/120329kr61q3oe6rw86ac1.png',
      );
    });

    test('parses older mobile comic thread with large inline image set', () {
      final html = File('docs/html/移动端html/漫画帖2.html').readAsStringSync();

      final result = parser.parse(html, fallbackTid: '499220', fallbackPage: 1);

      expect(result.tid, '499220');
      expect(result.fid, '30');
      expect(result.typeName, '長篇連載');
      expect(result.subject, '[Kirara漢化組][月刊コミック電撃大王][仲谷鳰]終將成為妳 第四十四話');
      expect(result.posts, isNotEmpty);

      final firstPost = result.posts.first;
      expect(firstPost.pid, '39360959');
      expect(firstPost.author, 'atj');
      expect(firstPost.message, contains('改圖僅供試看'));
      expect(
        firstPost.message,
        contains(
          'src="data/attachment/forum/201908/28/001314yjq2hkh7qjh3uhap.jpg"',
        ),
      );
      expect(
        firstPost.message,
        contains('src="http://qimg.hxnews.com/2019/0710/1562727280983.jpg"'),
      );
      expect(
        firstPost.message,
        isNot(contains('static/image/common/none.gif')),
      );

      final sources = DefaultForumImageSourcePipeline.collectDomImageSources(
        firstPost.message,
        urlResolver: const SiteUrlResolver(),
        domAttributes: const <String>[
          'zoomfile',
          'file',
          'data-original',
          'data-src',
          'src',
        ],
      );
      expect(sources, hasLength(37));
      expect(
        sources.first.normalizedUrl,
        'https://bbs.yamibo.com/data/attachment/forum/201908/28/001314yjq2hkh7qjh3uhap.jpg',
      );
      expect(
        sources.last.normalizedUrl,
        'http://qimg.hxnews.com/2019/0710/1562727280983.jpg',
      );
    });

    test('parses mobile poll result thread and keeps floor action urls', () {
      final html = File('docs/html/移动端html/一个投票帖.html').readAsStringSync();

      final result = parser.parse(html, fallbackTid: '565687', fallbackPage: 1);

      expect(result.tid, '565687');
      expect(result.fid, '33');
      expect(result.subject, '大家能接受自己看百合的事情，被别人知道吗？');
      expect(result.posts, isNotEmpty);

      final firstPost = result.posts.first;
      expect(firstPost.pid, '41437380');
      expect(firstPost.replyUrl, contains('action=reply'));
      expect(firstPost.rateUrl, contains('action=rate'));
      expect(firstPost.commentUrl, contains('action=comment'));
      expect(firstPost.message, contains('我爱看百合的事'));
      expect(firstPost.message, isNot(contains('单选投票, 共有 960 人参与投票')));
      expect(firstPost.message, isNot(contains('class="poll"')));
      expect(firstPost.message, isNot(contains('name="pollanswers[]"')));

      final poll = firstPost.poll;
      expect(poll, isNotNull);
      expect(poll!.isMultipleChoice, isFalse);
      expect(poll.canVote, isFalse);
      expect(poll.summary, '单选投票, 共有 960 人参与投票');
      expect(poll.deadlineText, contains('距结束还有'));
      expect(poll.statusText, '您已经投过票，谢谢您的参与');
      expect(poll.formHash, '041e5224');
      expect(poll.options, hasLength(7));
      expect(poll.options.first.id, '1');
      expect(poll.options.first.label, '不希望');
      expect(poll.options.first.percent, 10.94);
      expect(poll.options.first.voteCount, 105);
      expect(poll.options.first.colorHex, '#E92725');
      expect(poll.options[5].label, '不希望太多人知道');
      expect(poll.options[5].percent, 30.52);
      expect(poll.options[5].voteCount, 293);
      expect(poll.options.last.label, '其他');
      expect(poll.options.last.percent, 1.04);
      expect(poll.options.last.voteCount, 10);
    });

    test(
      'removes desktop thread obfuscation nodes before keeping message html',
      () {
        final result = parser.parse(
          _desktopObfuscatedThreadHtml,
          fallbackTid: '123456',
          fallbackPage: 1,
        );

        final firstPost = result.posts.single;
        expect(firstPost.message, contains('正常正文'));
        expect(firstPost.message, contains('保留文本'));
        expect(firstPost.message, isNot(contains('干扰A')));
        expect(firstPost.message, isNot(contains('干扰B')));
        expect(firstPost.message, isNot(contains('干扰C')));
        expect(firstPost.message, isNot(contains('jammer')));
      },
    );

    test(
      'removes desktop comment obfuscation text before extracting plain text',
      () {
        final result = parser.parse(
          _desktopCommentObfuscatedThreadHtml,
          fallbackTid: '123457',
          fallbackPage: 1,
        );

        final firstPost = result.posts.single;
        expect(firstPost.comments, hasLength(1));
        expect(firstPost.comments.single.message, '点评正文 保留文本');
        expect(firstPost.comments.single.message, isNot(contains('干扰点评')));
        expect(firstPost.comments.single.message, isNot(contains('隐藏点评')));
      },
    );

    test(
      'removes jammer and hidden spans from real obfuscated mobile thread html',
      () {
        final html = File('docs/html/被混淆的html/贴图区帖子.html').readAsStringSync();

        final result = parser.parse(
          html,
          fallbackTid: '544684',
          fallbackPage: 1,
        );

        final firstPost = result.posts.first;
        expect(firstPost.pid, '40951752');
        expect(firstPost.author, '玉枫kaete');
        expect(firstPost.message, contains('注意：主要更新《与你相恋到生命尽头》的同人图'));
        expect(firstPost.message, contains('社畜工作党所以更新应该会很慢。'));
        expect(firstPost.message, contains('不嫌弃的话请吃吃看孩子做的饭饭。'));
        expect(firstPost.message, isNot(contains('! R4 I1 a9 @+ H5 g')));
        expect(firstPost.message, isNot(contains('2 i"')));
        expect(firstPost.message, isNot(contains('# Q% \\; I: }')));
        expect(firstPost.comments.first.message, '好萌好萌好萌');
        expect(firstPost.comments.last.message, '画得好好看啊啊啊啊老师你是我的主人');
      },
    );
  });
}

const _alreadyVotedPollThreadHtml = '''
<html>
  <body>
    <div id="postlist">
      <div id="post_41474948">
        <td class="plc">
          <div class="pi">
            <strong><a id="postnum41474948"><em>1</em><sup>#</sup></a></strong>
            <div class="pti"><div class="authi"><em id="authorposton41474948">发表于 2026-6-20 12:00</em></div></div>
          </div>
          <td class="t_f" id="postmessage_41474948"><p>投票正文</p></td>
          <form id="poll" name="poll" method="post" autocomplete="off" action="forum.php?mod=misc&amp;action=votepoll&amp;fid=33&amp;tid=567764&amp;pollsubmit=yes&amp;quickforward=yes">
            <input type="hidden" name="formhash" value="cba80c43">
            <div class="pinf">
              <strong>多选投票</strong>: ( 最多可选 3 项 ), 共有 331 人参与投票
            </div>
            <p class="ptmr">
              距结束还有:
              <strong>9878 天21 小时0 分钟</strong>
            </p>
            <div class="pcht">
              <table summary="poll panel" cellspacing="0" cellpadding="0" width="100%">
                <tbody>
                  <tr>
                    <td class="pvt"><label for="option_1">1. &nbsp;两个心灵靠近的过程</label></td>
                    <td class="pvts"></td>
                  </tr>
                  <tr>
                    <td><div class="pbg"><div class="pbr" style="width: 39%; background-color:#E92725"></div></div></td>
                    <td>38.82% <em style="color:#E92725">(276)</em></td>
                  </tr>
                  <tr>
                    <td class="pvt"><label for="option_2">2. &nbsp;背德扭曲神人爆爆爆</label></td>
                    <td class="pvts"></td>
                  </tr>
                  <tr>
                    <td><div class="pbg"><div class="pbr" style="width: 11%; background-color:#F27B21"></div></div></td>
                    <td>11.25% <em style="color:#F27B21">(80)</em></td>
                  </tr>
                  <tr>
                    <td class="pvt"><label for="option_3">3. &nbsp;与世俗斗争的宿命感</label></td>
                    <td class="pvts"></td>
                  </tr>
                  <tr>
                    <td><div class="pbg"><div class="pbr" style="width: 6%; background-color:#F2A61F"></div></div></td>
                    <td>5.63% <em style="color:#F2A61F">(40)</em></td>
                  </tr>
                  <tr>
                    <td class="pvt"><label for="option_4">4. &nbsp;这样那样的萌萌互动</label></td>
                    <td class="pvts"></td>
                  </tr>
                  <tr>
                    <td><div class="pbg"><div class="pbr" style="width: 21%; background-color:#5AAF4A"></div></div></td>
                    <td>21.10% <em style="color:#5AAF4A">(150)</em></td>
                  </tr>
                  <tr>
                    <td class="pvt"><label for="option_5">5. &nbsp;这样那样的扣扣空间</label></td>
                    <td class="pvts"></td>
                  </tr>
                  <tr>
                    <td><div class="pbg"><div class="pbr" style="width: 14%; background-color:#42C4F5"></div></div></td>
                    <td>13.50% <em style="color:#42C4F5">(96)</em></td>
                  </tr>
                  <tr>
                    <td class="pvt"><label for="option_6">6. &nbsp;直掰弯和性向的探索</label></td>
                    <td class="pvts"></td>
                  </tr>
                  <tr>
                    <td><div class="pbg"><div class="pbr" style="width: 3%; background-color:#0099CC"></div></div></td>
                    <td>3.23% <em style="color:#0099CC">(23)</em></td>
                  </tr>
                  <tr>
                    <td class="pvt"><label for="option_7">7. &nbsp;怎样都好是百合就看</label></td>
                    <td class="pvts"></td>
                  </tr>
                  <tr>
                    <td><div class="pbg"><div class="pbr" style="width: 6%; background-color:#3365AE"></div></div></td>
                    <td>6.47% <em style="color:#3365AE">(46)</em></td>
                  </tr>
                  <tr>
                    <td colspan="2">您已经投过票，谢谢您的参与</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </form>
        </td>
      </div>
    </div>
  </body>
</html>
''';

const _desktopObfuscatedThreadHtml = '''
<html>
  <body>
    <div class="pg"><strong>1</strong></div>
    <div id="postlist">
      <div id="post_500001">
        <div class="pls">
          <div class="avatar"><img src="avatar.jpg" /></div>
          <div class="pi">
            <div class="authi">
              <a class="xw1" href="home.php?mod=space&amp;uid=42">Tester</a>
            </div>
          </div>
        </div>
        <div class="plc">
          <div class="pi">
            <strong><a id="postnum500001"><em>1</em><sup>#</sup></a></strong>
            <div class="pti">
              <div class="authi"><em id="authorposton500001">发表于 2026-7-2 10:00</em></div>
            </div>
          </div>
          <div class="t_f" id="postmessage_500001">
            <p>正常正文</p>
            <font class="jammer">干扰A</font>
            <span class="jammer">干扰B</span>
            <span style="display: none">干扰C</span>
            <span style="display : inline">保留文本</span>
          </div>
        </div>
      </div>
    </div>
  </body>
</html>
''';

const _desktopCommentObfuscatedThreadHtml = '''
<html>
  <body>
    <div class="pg"><strong>1</strong></div>
    <div id="postlist">
      <div id="post_500002">
        <div class="pls">
          <div class="avatar"><img src="avatar.jpg" /></div>
          <div class="pi">
            <div class="authi">
              <a class="xw1" href="home.php?mod=space&amp;uid=43">CommentOwner</a>
            </div>
          </div>
        </div>
        <div class="plc">
          <div class="pi">
            <strong><a id="postnum500002"><em>1</em><sup>#</sup></a></strong>
            <div class="pti">
              <div class="authi"><em id="authorposton500002">发表于 2026-7-2 10:05</em></div>
            </div>
          </div>
          <div class="t_f" id="postmessage_500002">
            <p>楼层正文</p>
          </div>
          <div id="comment_500002" class="cm">
            <div class="pstl">
              <div class="psta">
                <a class="xi2" href="home.php?mod=space&amp;uid=99">Commenter</a>
              </div>
              <div class="psti">
                点评正文
                <font class="jammer">干扰点评</font>
                <span style="display:none">隐藏点评</span>
                <span>保留文本</span>
                <span class="xg1">发表于 2026-7-2 10:06</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </body>
</html>
''';
