import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/thread_detail_html_parser.dart';

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
        expect(firstPost.replyUrl, contains('action=reply'));
        expect(firstPost.rateSummary, contains('参与人数'));

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
  });
}
