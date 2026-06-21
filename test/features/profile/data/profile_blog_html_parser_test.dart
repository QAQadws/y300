import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/data/models/profile_blog_models.dart';
import 'package:y300/features/profile/data/profile_blog_html_parser.dart';

void main() {
  const parser = ProfileBlogHtmlParser();

  test('ProfileBlogHtmlParser parses latest public blog list sample', () {
    final html = File('docs/html/我的日志/随便看看-最新发表的日志.html').readAsStringSync();

    final page = parser.parseList(
      html,
      fallbackView: ProfileBlogView.all,
      fallbackOrder: ProfileBlogOrder.latest,
    );

    expect(page.title, '日志');
    expect(page.activeView, ProfileBlogView.all);
    expect(page.activeOrder, ProfileBlogOrder.latest);
    expect(page.viewTabs.map((tab) => tab.label), ['好友的日志', '我的日志', '随便看看']);
    expect(page.orderTabs.map((tab) => tab.label), ['最新发表的日志', '推荐阅读的日志']);
    expect(page.items, hasLength(10));
    expect(page.items.first.id, '117558');
    expect(page.items.first.uid, '121614');
    expect(page.items.first.author, '抉择');
    expect(page.items.first.title, '一种体验');
    expect(page.items.first.excerpt, contains('作为女生'));
    expect(page.items.first.url, contains('id=117558'));
    expect(page.pagination?.currentPage, 1);
    expect(page.pagination?.totalPages, 6412);
    expect(page.pagination?.nextUrl, contains('page=2'));
  });

  test('ProfileBlogHtmlParser parses hot public blog list sample', () {
    final html = File('docs/html/我的日志/随便看看-推荐阅读的日志.html').readAsStringSync();

    final page = parser.parseList(
      html,
      fallbackView: ProfileBlogView.all,
      fallbackOrder: ProfileBlogOrder.hot,
    );

    expect(page.activeView, ProfileBlogView.all);
    expect(page.activeOrder, ProfileBlogOrder.hot);
    expect(page.items, hasLength(10));
    expect(page.items.first.id, '117548');
    expect(page.items.first.title, '我们小区的公共交通极其不便利');
    expect(page.pagination?.totalPages, 2637);
  });

  test('ProfileBlogHtmlParser parses empty mine and friends samples', () {
    final mineHtml = File('docs/html/我的日志/我的日志.html').readAsStringSync();
    final friendsHtml = File('docs/html/我的日志/好友的日志.html').readAsStringSync();

    final mine = parser.parseList(
      mineHtml,
      fallbackView: ProfileBlogView.mine,
      fallbackOrder: ProfileBlogOrder.latest,
    );
    final friends = parser.parseList(
      friendsHtml,
      fallbackView: ProfileBlogView.friends,
      fallbackOrder: ProfileBlogOrder.latest,
    );

    expect(mine.activeView, ProfileBlogView.mine);
    expect(mine.items, isEmpty);
    expect(mine.emptyMessage, '还没有相关的日志');
    expect(friends.activeView, ProfileBlogView.friends);
    expect(friends.items, isEmpty);
    expect(friends.emptyMessage, '还没有相关的日志');
  });

  test('ProfileBlogHtmlParser parses blog detail sample', () {
    final html = File('docs/html/我的日志/一个日志.html').readAsStringSync();

    final detail = parser.parseDetail(
      html,
      fallbackUrl:
          'https://bbs.yamibo.com/home.php?mod=space&uid=257582&do=blog&id=117548&mobile=2',
    );

    expect(detail.id, '117548');
    expect(detail.uid, '257582');
    expect(detail.title, '我们小区的公共交通极其不便利');
    expect(detail.author, 'hsyhlj');
    expect(detail.dateline, '2026-6-18 00:25');
    expect(detail.views, 39);
    expect(detail.commentsCount, 5);
    expect(detail.messageHtml, contains('一直对着电脑屏幕'));
    expect(detail.actions.map((action) => action.label), ['收藏', '分享', '邀请']);
    expect(detail.comments, hasLength(5));
    expect(detail.comments.first.id, '646846');
    expect(detail.comments.first.author, 'thessky');
    expect(
      detail.comments.first.avatarUrl,
      contains('/uc_server/data/avatar/000/57/74/94_avatar_small.jpg'),
    );
    expect(detail.comments.first.messageHtml, contains('探险的感觉'));
    expect(detail.comments[1].messageHtml, contains('<div class="quote">'));
    expect(detail.comments[1].messageHtml, contains('<blockquote>'));
    expect(
      detail.comments[2].avatarUrl,
      contains('/uc_server/data/avatar/000/27/89/48_avatar_small.jpg'),
    );
    expect(
      detail.comments[2].messageHtml,
      contains('static/image/smiley/comcom/2.gif'),
    );
    expect(detail.commentForm?.blogId, '117548');
    expect(detail.commentForm?.formhash, 'cba80c43');
  });
}
