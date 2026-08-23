import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/profile/data/services/user_blog_detail_html_parser.dart';
import 'package:y300/features/profile/data/services/user_blog_directory_html_parser.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';

void main() {
  const directoryParser = UserBlogDirectoryHtmlParser();
  const detailParser = UserBlogDetailHtmlParser();
  const siteOrigin = 'https://bbs.yamibo.com/';

  test('parses latest public blog directory with exact pagination', () {
    final html = File('docs/html/我的日志/随便看看-最新发表的日志.html').readAsStringSync();

    final parsed = directoryParser.parse(
      html: html,
      query: const UserBlogDirectoryQuery.public(),
      siteOrigin: siteOrigin,
    );

    expect(parsed.data.scope, UserBlogFeedScope.public);
    expect(parsed.data.order, UserBlogOrder.latest);
    expect(parsed.data.items, hasLength(10));
    expect(parsed.data.items.first.blogId, '117558');
    expect(parsed.data.items.first.ownerUserId, '121614');
    expect(parsed.data.items.first.authorName, '抉择');
    expect(parsed.data.items.first.title, '一种体验');
    expect(parsed.data.items.first.excerpt, contains('作为女生'));
    expect(parsed.data.pagination.currentPage, 1);
    expect(parsed.data.pagination.totalPages, 6412);
    expect(parsed.data.pagination.hasNext, isTrue);
    expect(parsed.paginationPrecision, PaginationPrecision.exact);
  });

  test('parses recommended public blog directory', () {
    final html = File('docs/html/我的日志/随便看看-推荐阅读的日志.html').readAsStringSync();

    final parsed = directoryParser.parse(
      html: html,
      query: const UserBlogDirectoryQuery.public(
        order: UserBlogOrder.recommended,
      ),
      siteOrigin: siteOrigin,
    );

    expect(parsed.data.order, UserBlogOrder.recommended);
    expect(parsed.data.items, hasLength(10));
    expect(parsed.data.items.first.blogId, '117548');
    expect(parsed.data.items.first.title, '我们小区的公共交通极其不便利');
    expect(parsed.data.pagination.totalPages, 2637);
  });

  test('parses explicit empty self and friends directories', () {
    final selfHtml = File('docs/html/我的日志/我的日志.html').readAsStringSync();
    final friendsHtml = File('docs/html/我的日志/好友的日志.html').readAsStringSync();

    final self = directoryParser.parse(
      html: selfHtml,
      query: const UserBlogDirectoryQuery.self(),
      siteOrigin: siteOrigin,
    );
    final friends = directoryParser.parse(
      html: friendsHtml,
      query: const UserBlogDirectoryQuery.friends(),
      siteOrigin: siteOrigin,
    );

    expect(self.data.scope, UserBlogFeedScope.self);
    expect(self.data.items, isEmpty);
    expect(friends.data.scope, UserBlogFeedScope.friends);
    expect(friends.data.items, isEmpty);
  });

  test('parses detail and comments without action or form fields', () {
    final html = File('docs/html/我的日志/一个日志.html').readAsStringSync();

    final detail = detailParser.parse(
      html: html,
      query: const UserBlogDetailQuery(ownerUserId: '257582', blogId: '117548'),
      siteOrigin: siteOrigin,
    );

    expect(detail.blogId, '117548');
    expect(detail.ownerUserId, '257582');
    expect(detail.title, '我们小区的公共交通极其不便利');
    expect(detail.authorName, 'hsyhlj');
    expect(detail.publishedAtText, '2026-6-18 00:25');
    expect(detail.viewCount, 39);
    expect(detail.commentCount, 5);
    expect(detail.bodyHtml, contains('一直对着电脑屏幕'));
    expect(detail.comments, hasLength(5));
    expect(detail.comments.first.commentId, '646846');
    expect(detail.comments.first.authorName, 'thessky');
    expect(detail.comments.first.bodyHtml, contains('探险的感觉'));
    expect(detail.comments[1].bodyHtml, contains('<div class="quote">'));
    expect(detail.comments[1].bodyHtml, contains('<blockquote>'));
    expect(detail.commentsOpen, isTrue);
  });

  test('fails when pagination link changes feed identity', () {
    const html = '''
      <div class="dhnv"><a class="mon" href="home.php?mod=space&amp;do=blog&amp;view=all">All</a></div>
      <div id="dhnavs_li"><li class="mon"><a href="home.php?mod=space&amp;do=blog&amp;view=all">Latest</a></li></div>
      <div class="threadlist"><ul></ul></div>
      <div class="pg"><strong>1</strong><a class="nxt" href="home.php?mod=space&amp;do=blog&amp;view=we&amp;page=2">Next</a></div>
    ''';

    expect(
      () => directoryParser.parse(
        html: html,
        query: const UserBlogDirectoryQuery.public(),
        siteOrigin: siteOrigin,
      ),
      throwsFormatException,
    );
  });

  test('fails when non-public pagination carries a public-only order', () {
    const html = '''
      <div class="dhnv"><a class="mon" href="home.php?mod=space&amp;do=blog&amp;view=me">Mine</a></div>
      <div class="threadlist"><ul></ul></div>
      <div class="pg"><strong>1</strong><a class="nxt" href="home.php?mod=space&amp;do=blog&amp;view=me&amp;order=hot&amp;page=2">Next</a></div>
    ''';

    expect(
      () => directoryParser.parse(
        html: html,
        query: const UserBlogDirectoryQuery.self(),
        siteOrigin: siteOrigin,
      ),
      throwsFormatException,
    );
  });

  test('fails when feed identity is supplied by another origin', () {
    const html = '''
      <div class="dhnv"><a class="mon" href="https://example.com/home.php?mod=space&amp;do=blog&amp;view=all">All</a></div>
      <div id="dhnavs_li"><li class="mon"><a href="home.php?mod=space&amp;do=blog&amp;view=all">Latest</a></li></div>
      <div class="threadlist"><ul></ul></div>
    ''';

    expect(
      () => directoryParser.parse(
        html: html,
        query: const UserBlogDirectoryQuery.public(),
        siteOrigin: siteOrigin,
      ),
      throwsFormatException,
    );
  });

  test('fails when detail owner identity is supplied by another origin', () {
    const html = '''
      <div class="viewthread">
        <div class="view_tit">Blog</div>
        <div class="plc">
          <ul class="authi"><li class="mtit"><a href="https://example.com/home.php?mod=space&amp;uid=101">Owner</a></li></ul>
          <div class="message">Body</div>
          <div class="threadlist_foot"><a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=blog&amp;id=11">Favorite</a></div>
        </div>
      </div>
    ''';

    expect(
      () => detailParser.parse(
        html: html,
        query: const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'),
        siteOrigin: siteOrigin,
      ),
      throwsFormatException,
    );
  });
}
