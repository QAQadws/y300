import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/thread/data/thread_detail_html_parser.dart';
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
