import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

import '../support/blog_fixtures.dart';

void main() {
  late BlogFixtureNetwork network;
  late UserBlogNavigation navigation;
  setUp(() {
    network = BlogFixtureNetwork('');
    navigation = YamiboForumClientBuilder(
      config: blogConfig,
      network: network,
    ).buildStandardClient().blogNavigation!;
  });
  tearDown(() => expect(network.requests, isEmpty));

  for (final query in [
    const UserBlogDirectoryQuery.public(
      page: 3,
      order: UserBlogOrder.recommended,
      categoryId: '7',
    ),
    const UserBlogDirectoryQuery.friends(page: 2),
    const UserBlogDirectoryQuery.self(
      ownerUserId: '101',
      personalCategoryId: '8',
      page: 4,
    ),
    const UserBlogDirectoryQuery.self(),
  ]) {
    test(
      'outbound feed preserves its complete query on native reentry: $query',
      () {
        final reference =
            navigation.resolveReadReference(
                  navigation.directory(query).toString(),
                )
                as UserBlogDirectoryReference;
        expect(reference.query, query);
      },
    );
  }

  for (final query in [
    const UserBlogDetailQuery(ownerUserId: '101', blogId: '11', page: 3),
    const UserBlogDetailQuery(
      ownerUserId: '101',
      blogId: '11',
      commentId: '31',
    ),
    const UserBlogDetailQuery(
      ownerUserId: '101',
      blogId: '11',
      lastCommentPage: true,
    ),
  ]) {
    test(
      'outbound article preserves comment selection on native reentry: $query',
      () {
        final reference =
            navigation.resolveReadReference(navigation.detail(query).toString())
                as UserBlogDetailReference;
        expect(reference.query, query);
        expect(
          reference.focusComments,
          query.commentId != null || query.lastCommentPage,
        );
      },
    );
  }

  test(
    'relative, escaped and default HTTP references stay on the configured source',
    () {
      for (final prefix in [
        '',
        '/',
        'https://example.test/',
        'http://example.test/',
        '//example.test/',
      ]) {
        final reference =
            navigation.resolveReadReference(
                  '${prefix}home.php?mod=space&amp;uid=101&amp;do=profile',
                )
                as UserBlogAuthorReference;
        expect(reference.userId, '101');
      }
    },
  );

  test('comment anchors resolve against the actual article base', () {
    final base = navigation.detail(
      const UserBlogDetailQuery(ownerUserId: '101', blogId: '11', page: 2),
    )!;
    for (final fragment in [
      'comment',
      'quickcommentform_11',
      'comment_31',
      'comment_31_li',
    ]) {
      final reference =
          navigation.resolveReadReference('#$fragment', baseUri: base)
              as UserBlogDetailReference;
      expect(reference.query.ownerUserId, '101');
      expect(reference.query.blogId, '11');
      expect(reference.query.page, 2);
      expect(
        reference.query.commentId,
        fragment.startsWith('comment_') ? '31' : null,
      );
      expect(reference.focusComments, isTrue);
    }
    expect(
      navigation.resolveReadReference(
        '#comment',
        baseUri: Uri.parse(
          'https://elsewhere.test/home.php?mod=space&uid=101&do=blog&id=11',
        ),
      ),
      isNull,
    );
  });

  test('friends feed owner must match the currently resolved account', () {
    const link =
        'home.php?mod=space&do=blog&view=we&uid=101&order=dateline&page=2';
    final reference =
        navigation.resolveReadReference(link, actorUserId: '101')
            as UserBlogDirectoryReference;
    expect(reference.query, const UserBlogDirectoryQuery.friends(page: 2));
    expect(navigation.resolveReadReference(link, actorUserId: '202'), isNull);
    expect(navigation.resolveReadReference(link), isNull);
  });

  test('empty server pagination fields do not become native filters', () {
    final reference =
        navigation.resolveReadReference(
              'home.php?mod=space&do=blog&view=all&uid=101&catid=0&classid=&fuid=&clickid=&searchkey=&from=&friend=',
            )
            as UserBlogDirectoryReference;
    expect(reference.query, const UserBlogDirectoryQuery.public());
  });

  for (final suffix in [
    '&uid=202',
    '&%75id=202',
    '&id=12',
    '&page=0',
    '&page=-1',
    '&page=01',
    '&page=999999999999999999999999999999999999999',
    '&cid=0',
    '&cid=x',
    '&cid=31&goto=last',
    '&goto=other',
    '&modblogkey=secret',
    '&op=delete',
    '&formhash=secret',
    '&view=me',
    '&unknown=1',
    '&cid=%FF',
    '&cid=31#comment_32',
    '&goto=last#comment_31',
    '#quickcommentform_12',
    '#unknown',
  ]) {
    test(
      'article ambiguity or unsupported state stays in browser: $suffix',
      () {
        expect(
          navigation.resolveReadReference(
            'home.php?mod=space&do=blog&uid=101&id=11$suffix',
          ),
          isNull,
        );
      },
    );
  }

  for (final query in [
    'view=all&catid=x',
    'view=all&classid=8',
    'view=me&catid=7',
    'view=we&classid=8',
    'view=all&order=unknown',
    'view=me&order=hot',
    'view=we&order=hot',
    'view=all&searchkey=word',
    'view=we&fuid=202',
    'view=me&friend=4',
    'view=all&clickid=2',
    'view=me&from=space',
    'view=unknown',
    'uid=101',
    'view=all&uid=0',
    'view=all&mobile=2&mobile=no',
  ]) {
    test('unrepresented feed context is not silently discarded: $query', () {
      expect(
        navigation.resolveReadReference('home.php?mod=space&do=blog&$query'),
        isNull,
      );
    });
  }

  for (final link in [
    'https://elsewhere.test/home.php?mod=space&uid=101&do=profile',
    'https://example.test:8443/home.php?mod=space&uid=101&do=profile',
    'https://user:password@example.test/home.php?mod=space&uid=101&do=profile',
    'javascript:alert(1)',
    'data:text/html,test',
    'file:///home.php',
    '',
    'home.php?mod=spacecp&ac=blog&blogid=11&op=delete',
    'home.php?mod=space&do=blog&id=11',
    'home.php?mod=space&do=profile&username=someone',
    'home.php?mod=space&do=profile&uid=01',
    'home.php?mod=space&do=profile&uid=101&uid=202',
    'home.php?mod=space&do=profile&uid=101&unknown=1',
    'home.php?mod=space&do=profile&uid=101#comment',
  ]) {
    test(
      'unsafe, incomplete or nonread reference is not a native destination: $link',
      () {
        expect(navigation.resolveReadReference(link), isNull);
      },
    );
  }
}
