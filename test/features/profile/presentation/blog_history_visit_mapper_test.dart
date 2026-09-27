import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/blog_history_target.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/profile/presentation/blog/blog_history_visit_mapper.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../test_support/blog_navigation_fixture.dart';

void main() {
  const mapper = BlogHistoryVisitMapper(siteBaseUrl: 'https://example.test');

  test('keeps source metadata and maps only the first article image', () {
    final navigation = BlogNavigationFixture();
    final draft = mapper.map(
      data: _article(
        bodyHtml: '''
          <img src="data:image/gif;base64,placeholder">
          <img src="/static/image/smilies/default/smile.gif">
          <img src="/uc_server/data/avatar/author.jpg">
          <img data-original="/data/attachment/blog/first.jpg">
          <img src="https://cdn.example.test/second.jpg">
        ''',
      ),
      navigation: navigation,
    );

    expect(
      draft.target,
      BlogHistoryTarget(ownerUserId: '202', blogId: '11').key,
    );
    expect(draft.surface, HistoryVisitSurface.blogDetail);
    expect(draft.title, '原始标题');
    expect(draft.contextLabel, '原始作者');
    expect(
      draft.thumbnail?.remoteUrl,
      'https://example.test/data/attachment/blog/first.jpg',
    );
    expect(draft.canonicalUri, navigation.uri);
    expect(
      navigation.detailQuery,
      const UserBlogDetailQuery(ownerUserId: '202', blogId: '11'),
    );
    expect(draft.page, isNull);
    expect(draft.sourceTid, isNull);
    expect(draft.forumName, isNull);
  });

  test('neither the author avatar nor comment images become a thumbnail', () {
    final draft = mapper.map(data: _article(bodyHtml: '<p>文字正文</p>'));
    expect(draft.thumbnail, isNull);
    expect(draft.canonicalUri, isNull);
  });

  test('an empty successful article and unavailable navigation still map', () {
    final draft = mapper.map(data: _article(bodyHtml: ''));
    expect(draft.target.type, HistoryTargetType.blog);
    expect(draft.title, '原始标题');
    expect(draft.canonicalUri, isNull);
    expect(draft.thumbnail, isNull);
  });

  test('normalizes identities before building the canonical article link', () {
    final navigation = BlogNavigationFixture();
    final draft = mapper.map(
      data: _article(ownerUserId: ' 00202 ', blogId: '00011'),
      navigation: navigation,
    );
    expect(
      draft.target,
      BlogHistoryTarget(ownerUserId: '202', blogId: '11').key,
    );
    expect(navigation.detailQuery?.ownerUserId, '202');
    expect(navigation.detailQuery?.blogId, '11');
  });
}

UserBlogDetailData _article({
  String ownerUserId = '202',
  String blogId = '11',
  String bodyHtml = '<p>正文</p>',
}) => UserBlogDetailData(
  ownerUserId: ownerUserId,
  blogId: blogId,
  title: '原始标题',
  authorName: '原始作者',
  bodyHtml: bodyHtml,
  avatarUrl: 'https://example.test/uc_server/data/avatar/author.jpg',
  commentPagination: const UserBlogPagination(currentPage: 3, totalPages: 3),
  comments: const [
    UserBlogComment(
      commentId: '31',
      authorName: '评论作者',
      bodyHtml: '<img src="https://example.test/comment.jpg">',
    ),
  ],
);
