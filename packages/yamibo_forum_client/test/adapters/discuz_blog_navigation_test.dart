import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import '../support/blog_fixtures.dart';

void main() {
  UserBlogNavigation navigation([Uri? origin]) => ForumClientAdapterFactory(
    config: ForumClientConfig(
      siteOrigin: origin ?? Uri.parse('https://example.test'),
    ),
    network: BlogFixtureNetwork(''),
  ).createUserBlogNavigation();

  test('feed references keep the selected scope, order, category and page', () {
    final nav = navigation();
    expect(
      nav
          .directory(
            const UserBlogDirectoryQuery.public(
              order: UserBlogOrder.recommended,
              categoryId: '7',
              page: 3,
            ),
          )!
          .queryParameters,
      {
        'mod': 'space',
        'do': 'blog',
        'view': 'all',
        'order': 'hot',
        'catid': '7',
        'page': '3',
        'mobile': '2',
      },
    );
    expect(
      nav.directory(const UserBlogDirectoryQuery.friends())!.queryParameters,
      {'mod': 'space', 'do': 'blog', 'view': 'we', 'page': '1', 'mobile': '2'},
    );
    expect(
      nav
          .directory(
            const UserBlogDirectoryQuery.self(
              ownerUserId: '101',
              personalCategoryId: '8',
              page: 2,
            ),
          )!
          .queryParameters,
      {
        'mod': 'space',
        'do': 'blog',
        'view': 'me',
        'uid': '101',
        'classid': '8',
        'page': '2',
        'mobile': '2',
      },
    );
  });

  test('article references preserve filtered and last-page comment entry', () {
    final nav = navigation();
    final filtered = nav.detail(
      const UserBlogDetailQuery(
        ownerUserId: '101',
        blogId: '11',
        commentId: '31',
      ),
    )!;
    expect(filtered.queryParameters['cid'], '31');
    final last = nav.detail(
      const UserBlogDetailQuery(
        ownerUserId: '101',
        blogId: '11',
        lastCommentPage: true,
      ),
    )!;
    expect(last.queryParameters['goto'], 'last');
    expect(last.queryParameters, isNot(contains('page')));
    expect(last.host, 'example.test');
    expect(last.path, '/home.php');
  });

  for (final action in [UserBlogAction.create, UserBlogAction.edit]) {
    test('$action always uses the complete browser editor', () {
      final uri = navigation().editor(
        UserBlogTarget(
          actorUserId: '101',
          ownerUserId: '101',
          action: action,
          blogId: action == UserBlogAction.edit ? '11' : null,
        ),
      )!;
      expect(uri.queryParameters, {
        'mod': 'spacecp',
        'ac': 'blog',
        'mobile': 'no',
        if (action == UserBlogAction.edit) 'blogid': '11',
        if (action == UserBlogAction.edit) 'op': 'edit',
      });
    });
  }

  for (final action in UserBlogCommentAction.values) {
    test(
      '$action references a form without formhash or callback credentials',
      () {
        final uri = navigation().comment(
          UserBlogCommentTarget(
            actorUserId: '101',
            ownerUserId: '202',
            blogId: '11',
            action: action,
            commentId: action == UserBlogCommentAction.add ? null : '31',
          ),
        )!;
        if (action == UserBlogCommentAction.add) {
          expect(uri.fragment, 'quickcommentform_11');
          expect(uri.queryParameters['id'], '11');
        } else {
          expect(uri.queryParameters, {
            'mod': 'spacecp',
            'ac': 'comment',
            'op': action.name,
            'cid': '31',
            'mobile': '2',
          });
        }
        expect(uri.queryParameters, isNot(contains('formhash')));
        expect(uri.queryParameters, isNot(contains('handlekey')));
        expect(uri.queryParameters, isNot(contains('referer')));
      },
    );
  }

  for (final id in ['', '0', '-1', ' 101', '1&formhash=secret', '01', 'a']) {
    test('invalid identity $id cannot produce a navigation reference', () {
      final nav = navigation();
      expect(
        nav.detail(UserBlogDetailQuery(ownerUserId: id, blogId: '11')),
        isNull,
      );
      expect(
        nav.directory(UserBlogDirectoryQuery.self(ownerUserId: id)),
        isNull,
      );
      expect(
        nav.directory(UserBlogDirectoryQuery.public(categoryId: id)),
        isNull,
      );
      expect(
        nav.editor(
          UserBlogTarget(
            actorUserId: '101',
            ownerUserId: '101',
            action: UserBlogAction.edit,
            blogId: id,
          ),
        ),
        isNull,
      );
      expect(
        nav.comment(
          UserBlogCommentTarget(
            actorUserId: '101',
            ownerUserId: '202',
            blogId: '11',
            action: UserBlogCommentAction.reply,
            commentId: id,
          ),
        ),
        isNull,
      );
    });
  }

  test('incomplete or inconsistent operations have no form destination', () {
    final nav = navigation();
    expect(
      nav.directory(const UserBlogDirectoryQuery.self())!.queryParameters,
      isNot(contains('uid')),
    );
    expect(nav.directory(const UserBlogDirectoryQuery.public(page: 0)), isNull);
    expect(
      nav.detail(
        const UserBlogDetailQuery(
          ownerUserId: '101',
          blogId: '11',
          commentId: '31',
          lastCommentPage: true,
        ),
      ),
      isNull,
    );
    expect(
      nav.editor(
        const UserBlogTarget(
          actorUserId: '101',
          ownerUserId: '202',
          action: UserBlogAction.create,
        ),
      ),
      isNull,
    );
    expect(
      nav.editor(
        const UserBlogTarget(
          actorUserId: '101',
          ownerUserId: '101',
          blogId: '11',
          action: UserBlogAction.create,
        ),
      ),
      isNull,
    );
    expect(
      nav.editor(
        const UserBlogTarget(
          actorUserId: '101',
          ownerUserId: '101',
          blogId: '11',
          action: UserBlogAction.delete,
        ),
      ),
      isNull,
    );
    expect(
      nav.comment(
        const UserBlogCommentTarget(
          actorUserId: '101',
          ownerUserId: '101',
          blogId: '11',
          action: UserBlogCommentAction.add,
          commentId: '31',
        ),
      ),
      isNull,
    );
  });

  for (final source in [
    'file:///tmp',
    'javascript:alert(1)',
    'https://user:password@example.test',
    'https://example.test/?secret=value',
    'https://example.test/#private',
    'https://example.test/unrelated/',
  ]) {
    test('invalid source origin is not used: $source', () {
      expect(
        navigation(
          Uri.parse(source),
        ).directory(const UserBlogDirectoryQuery.public()),
        isNull,
      );
    });
  }

  test(
    'source overlays and facade preserve independently replaceable navigation',
    () {
      final nav = navigation();
      final network = BlogFixtureNetwork('');
      final client =
          YamiboForumClientBuilder(
            config: blogConfig,
            network: network,
          ).buildStandardClient(
            sourceOverrides: ForumClientSourcePlan(blogNavigation: nav),
          );
      expect(client.blogNavigation, same(nav));
      expect(
        client.blogNavigation!.detail(
          const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'),
        ),
        isNotNull,
      );
      expect(network.requests, isEmpty);
    },
  );
}
