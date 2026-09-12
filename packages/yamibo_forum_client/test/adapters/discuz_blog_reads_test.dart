import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import '../support/blog_fixtures.dart';

void main() {
  ForumClientAdapterFactory factory(BlogFixtureNetwork network) =>
      ForumClientAdapterFactory(config: blogConfig, network: network);
  const article = UserBlogDetailQuery(ownerUserId: '101', blogId: '11');

  test(
    'directory actions come from the management row, not article text',
    () async {
      final source = blogFeed(view: 'me', owner: '101')
          .replaceFirst('<div class="mtime">', '''<div class="doing_listgl">
          <a href="home.php?mod=spacecp&ac=blog&op=edit&blogid=11">Edit</a>
          <a href="home.php?mod=spacecp&ac=blog&op=delete&blogid=11">Delete</a>
          <a href="home.php?mod=spacecp&ac=blog&op=stick&blogid=11&stickflag=1">Pin</a>
        </div><div class="mtime">''')
          .replaceFirst(
            'An excerpt',
            '<a href="home.php?mod=spacecp&ac=blog&op=stick&blogid=11&stickflag=0">Unrelated content</a>',
          );
      final result = await factory(BlogFixtureNetwork(source))
          .createUserBlogDirectory()
          .load(const UserBlogDirectoryQuery.self(ownerUserId: '101'));
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.items.single.actions, {
        UserBlogAction.edit,
        UserBlogAction.delete,
        UserBlogAction.pin,
      });
    },
  );

  test('detail exposes only validated management links', () async {
    final source = blogArticle(editOnly: true).replaceFirst(
      '>Action</a>',
      '''>Action</a>
      <a href="home.php?mod=spacecp&ac=blog&op=delete&blogid=11">Delete</a>
      <a href="home.php?mod=spacecp&ac=blog&op=stick&blogid=11&stickflag=0">Unpin</a>''',
    );
    final result = await factory(
      BlogFixtureNetwork(source),
    ).createUserBlogDetail().load(article);
    expect(result.failureOrNull, isNull);
    expect(result.dataOrNull!.actions, {
      UserBlogAction.edit,
      UserBlogAction.delete,
      UserBlogAction.unpin,
    });
  });

  for (final uri in [
    'https://external.test/home.php?mod=spacecp&ac=blog&op=delete&blogid=11',
    'http://example.test/home.php?mod=spacecp&ac=blog&op=delete&blogid=11',
    'https://example.test:444/home.php?mod=spacecp&ac=blog&op=delete&blogid=11',
    'home.php?mod=spacecp&ac=blog&op=delete&blogid=11&blogid=99',
    'home.php?mod=spacecp&ac=blog&op=delete&blogid=11&modblogkey=unverified',
  ]) {
    test('unverified endpoint is not an advertised action: $uri', () async {
      final source = blogArticle().replaceFirst(
        '>Action</a>',
        '>Action</a><a href="$uri">Delete</a>',
      );
      final result = await factory(
        BlogFixtureNetwork(source),
      ).createUserBlogDetail().load(article);
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.actions, isEmpty);
    });
  }

  for (final (query, view) in [
    (const UserBlogDirectoryQuery.public(), 'all'),
    (const UserBlogDirectoryQuery.friends(), 'we'),
    (const UserBlogDirectoryQuery.self(ownerUserId: '101'), 'me'),
  ]) {
    test(
      'loads $view through one mobile request and proves terminal page',
      () async {
        final network = BlogFixtureNetwork(
          blogFeed(view: view, owner: query.ownerUserId),
        );
        final result = await factory(
          network,
        ).createUserBlogDirectory().load(query);
        expect(result.failureOrNull, isNull);
        expect(result.dataOrNull!.items.single.title, 'Title & punctuation');
        expect(result.dataOrNull!.pagination.hasNext, isFalse);
        expect(network.requests, hasLength(1));
        expect(
          network.requests.single.uri.queryParameters,
          containsPair('mobile', '2'),
        );
        expect(
          network.requests.single.uri.queryParameters,
          containsPair('view', view),
        );
        expect(network.requests.single.method, ForumRequestMethod.get);
      },
    );
  }

  test(
    'public category keeps recommended ordering and exposes filters',
    () async {
      final network = BlogFixtureNetwork(blogFeed(order: 'hot', category: '8'));
      final result = await factory(network).createUserBlogDirectory().load(
        const UserBlogDirectoryQuery.public(
          order: UserBlogOrder.recommended,
          categoryId: '8',
        ),
      );
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.categories.single.id, '8');
      expect(
        network.requests.single.uri.queryParameters,
        containsPair('order', 'hot'),
      );
      expect(
        network.requests.single.uri.queryParameters,
        containsPair('catid', '8'),
      );
    },
  );

  test('personal category and explicit owner survive paging', () async {
    final network = BlogFixtureNetwork(
      blogFeed(
        view: 'me',
        owner: '101',
        personalCategory: '7',
        page: 2,
        pages: 3,
      ),
    );
    final result = await factory(network).createUserBlogDirectory().load(
      const UserBlogDirectoryQuery.self(
        ownerUserId: '101',
        personalCategoryId: '7',
        page: 2,
      ),
    );
    expect(result.failureOrNull, isNull);
    expect(result.dataOrNull!.pagination.currentPage, 2);
    expect(result.dataOrNull!.pagination.hasNext, isTrue);
    expect(
      network.requests.single.uri.queryParameters,
      containsPair('classid', '7'),
    );
  });

  test('empty friends feed is a successful terminal page', () async {
    final result = await factory(
      BlogFixtureNetwork(blogFeed(view: 'we', empty: true)),
    ).createUserBlogDirectory().load(const UserBlogDirectoryQuery.friends());
    expect(result.failureOrNull, isNull);
    expect(result.dataOrNull!.items, isEmpty);
    expect(result.dataOrNull!.pagination.hasNext, isFalse);
  });

  for (final query in [
    const UserBlogDirectoryQuery.public(categoryId: '8'),
    const UserBlogDirectoryQuery.public(order: UserBlogOrder.recommended),
    const UserBlogDirectoryQuery.self(ownerUserId: '999'),
  ]) {
    test('rejects another scope, owner, category or order: $query', () async {
      final result = await factory(
        BlogFixtureNetwork(blogFeed()),
      ).createUserBlogDirectory().load(query);
      expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
    });
  }

  for (final query in [
    const UserBlogDirectoryQuery.public(page: 0),
    const UserBlogDirectoryQuery.self(ownerUserId: '-1'),
    const UserBlogDirectoryQuery(
      scope: UserBlogFeedScope.friends,
      categoryId: '8',
    ),
    const UserBlogDirectoryQuery(
      scope: UserBlogFeedScope.public,
      personalCategoryId: '7',
    ),
  ]) {
    test('invalid feed queries send no request: $query', () async {
      final network = BlogFixtureNetwork('');
      final result = await factory(
        network,
      ).createUserBlogDirectory().load(query);
      expect(result.failureOrNull!.kind, DataReadFailureKind.business);
      expect(network.requests, isEmpty);
    });
  }

  test('reads later comment pages while preserving article markup', () async {
    final network = BlogFixtureNetwork(blogArticle(page: 2, pages: 3));
    final result = await factory(network).createUserBlogDetail().load(
      const UserBlogDetailQuery(ownerUserId: '101', blogId: '11', page: 2),
    );
    expect(result.failureOrNull, isNull);
    expect(result.dataOrNull!.bodyHtml, contains('<b>rich text</b>'));
    expect(result.dataOrNull!.commentPagination.currentPage, 2);
    expect(result.dataOrNull!.commentPagination.hasNext, isTrue);
    expect(
      network.requests.single.uri.queryParameters,
      containsPair('page', '2'),
    );
  });

  test('last-page lookup uses server evidence', () async {
    final network = BlogFixtureNetwork(blogArticle(page: 3, pages: 3));
    final result = await factory(network).createUserBlogDetail().load(
      const UserBlogDetailQuery(
        ownerUserId: '101',
        blogId: '11',
        lastCommentPage: true,
      ),
    );
    expect(result.failureOrNull, isNull);
    expect(result.dataOrNull!.commentPagination.currentPage, 3);
    expect(
      network.requests.single.uri.queryParameters,
      containsPair('goto', 'last'),
    );
  });

  test(
    'anonymous comments and disabled replies do not hide an article',
    () async {
      final result = await factory(
        BlogFixtureNetwork(
          blogArticle(anonymous: true, commentsOpen: false, editOnly: true),
        ),
      ).createUserBlogDetail().load(article);
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.comments.single.authorName, 'Anonymous');
      expect(result.dataOrNull!.comments.single.authorUserId, isNull);
      expect(result.dataOrNull!.commentsOpen, isFalse);
    },
  );

  test('specific-comment links cannot accept unrelated comments', () async {
    final network = BlogFixtureNetwork(blogArticle(commentId: '9'));
    final result = await factory(network).createUserBlogDetail().load(
      const UserBlogDetailQuery(
        ownerUserId: '101',
        blogId: '11',
        commentId: '5',
      ),
    );
    expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
    expect(
      network.requests.single.uri.queryParameters,
      containsPair('cid', '5'),
    );
  });

  for (final replacement in [
    'https://external.test/home.php?mod=space&uid=101&do=blog&id=11&page=2',
    'home.php?mod=space&uid=101&do=blog&id=99&page=2',
    'home.php?mod=space&uid=999&do=blog&id=11&page=2',
    'home.php?mod=space&uid=101&do=blog&id=11&page=3',
  ]) {
    test(
      'rejects untrusted or mismatched comment pager: $replacement',
      () async {
        final source = blogArticle(pages: 3).replaceAll(
          'home.php?mod=space&uid=101&do=blog&id=11&page=2',
          replacement,
        );
        final result = await factory(
          BlogFixtureNetwork(source),
        ).createUserBlogDetail().load(article);
        expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
      },
    );
  }

  for (final (source, code, kind) in [
    (
      '<form id="loginform"></form>',
      'user_blog_login_required',
      DataReadFailureKind.unauthorized,
    ),
    (
      '<form id="invalueform"><input name="viewpwd" type="password"></form>',
      'user_blog_password_required',
      DataReadFailureKind.business,
    ),
    (
      '<div id="ct"><div class="nfl"><div class="f_c"><table><tr><td><div class="avt"></div><a href="home.php?mod=space&uid=101&do=friend">Friends</a></td></tr></table></div></div></div>',
      'user_blog_private',
      DataReadFailureKind.business,
    ),
    (
      '<div id="messagetext">private server payload</div>',
      'user_blog_unavailable',
      DataReadFailureKind.business,
    ),
  ]) {
    test('classifies $code without leaking server text', () async {
      final result = await factory(
        BlogFixtureNetwork(source),
      ).createUserBlogDetail().load(article);
      expect(result.failureOrNull!.kind, kind);
      expect(result.failureOrNull!.code, code);
      expect(
        result.failureOrNull!.diagnosticMessage,
        isNot(contains('private server payload')),
      );
    });
  }

  for (final beforeSend in [true, false]) {
    test(
      'cancelled article read discards ${beforeSend ? 'unsent' : 'late'} response',
      () async {
        final cancellation = ForumRequestCancellation();
        if (beforeSend) cancellation.cancel();
        final network = BlogFixtureNetwork(
          blogArticle(),
          beforeResponse: cancellation.cancel,
        );
        final result = await factory(
          network,
        ).createUserBlogDetail().load(article, cancellation: cancellation);
        expect(result.failureOrNull!.kind, DataReadFailureKind.cancelled);
        expect(network.requests, hasLength(beforeSend ? 0 : 1));
        if (!beforeSend) {
          expect(network.requests.single.cancellation, same(cancellation));
        }
      },
    );
    test(
      'cancelled feed read discards ${beforeSend ? 'unsent' : 'late'} response',
      () async {
        final cancellation = ForumRequestCancellation();
        if (beforeSend) cancellation.cancel();
        final network = BlogFixtureNetwork(
          blogFeed(),
          beforeResponse: cancellation.cancel,
        );
        final result = await factory(network).createUserBlogDirectory().load(
          const UserBlogDirectoryQuery.public(),
          cancellation: cancellation,
        );
        expect(result.failureOrNull!.kind, DataReadFailureKind.cancelled);
        expect(network.requests, hasLength(beforeSend ? 0 : 1));
      },
    );
  }
}
