import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import '../support/blog_fixtures.dart';

void main() {
  Future<UserBlogDetailData> read(String heading) async {
    final network = BlogFixtureNetwork(blogArticle(heading: heading));
    final result =
        await ForumClientAdapterFactory(config: blogConfig, network: network)
            .createUserBlogDetail()
            .load(const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'));
    expect(result.failureOrNull, isNull);
    expect(network.requests, hasLength(1));
    return result.dataOrNull!;
  }

  test(
    'touch heading separates author and site categories from the subject',
    () async {
      final data = await read('''
      <!-- template whitespace -->
      <em>[<a href="home.php?mod=space&amp;uid=101&amp;do=blog&amp;classid=7&amp;view=me">作者分类</a>]</em>
      <em>[<a href="/home.php?mod=space&amp;do=blog&amp;view=all&amp;catid=8">故事 &amp; [随笔]</a>]</em>
      [Actual] title &amp; punctuation <span>(Pending)</span>
    ''');
      expect(data.title, '[Actual] title & punctuation (Pending)');
      expect(data.categoryLinks.map((link) => link.name), [
        '作者分类',
        '故事 & [随笔]',
      ]);
      expect(data.categoryLinks.map((link) => link.query), [
        const UserBlogDirectoryQuery.self(
          ownerUserId: '101',
          personalCategoryId: '7',
        ),
        const UserBlogDirectoryQuery.public(categoryId: '8'),
      ]);
      expect(() => data.categoryLinks.clear(), throwsUnsupportedError);
    },
  );

  test('categories retain the full advertised order and page', () async {
    final data = await read('''
      <em>[<a href="https://example.test/home.php?mod=space&do=blog&view=all&catid=8&order=hot&page=3">Recommended category</a>]</em>Title
    ''');
    expect(data.title, 'Title');
    expect(
      data.categoryLinks.single.query,
      const UserBlogDirectoryQuery.public(
        categoryId: '8',
        order: UserBlogOrder.recommended,
        page: 3,
      ),
    );
  });

  for (final reference in [
    'https://outside.test/home.php?mod=space&do=blog&view=all&catid=8',
    'https://example.test:444/home.php?mod=space&do=blog&view=all&catid=8',
    'home.php?mod=space&do=blog&view=all&catid=8&catid=9',
    'home.php?mod=space&do=blog&view=all&catid=invalid',
    'home.php?mod=space&do=blog&view=all&catid=0',
    'home.php?mod=space&do=blog&view=all&catid=8&searchkey=unknown',
    'home.php?mod=space&do=blog&view=me&classid=7',
    'home.php?mod=space&uid=202&do=blog&view=me&classid=7',
    'home.php?mod=space&do=blog&view=we',
    'home.php?mod=space&uid=101&do=blog&id=11',
    'home.php?mod=spacecp&ac=blog&op=delete&blogid=11',
    'javascript:alert(1)',
  ]) {
    test(
      'unproven category remains readable without a guessed link: $reference',
      () async {
        final data = await read(
          '<em>[<a href="$reference">Unknown category</a>]</em> Title',
        );
        expect(data.categoryLinks, isEmpty);
        expect(data.title, '[Unknown category] Title');
      },
    );
  }

  test('only leading template category wrappers become links', () async {
    const link =
        '<a href="home.php?mod=space&do=blog&view=all&catid=8">Category</a>';
    final data = await read('Title <em>[$link]</em>');
    expect(data.title, 'Title [Category]');
    expect(data.categoryLinks, isEmpty);
    final duplicate = await read('<em>[$link]</em><em>[$link]</em>Title');
    expect(duplicate.title, 'Title');
    expect(duplicate.categoryLinks, hasLength(1));
  });

  test(
    'list categories are labels and preserve the same detail subject',
    () async {
      final network = BlogFixtureNetwork(
        blogFeed().replaceFirst(
          'Title &amp; punctuation',
          '<span>[Site category]</span> <span>[Author category]</span> [Actual] title &amp; punctuation',
        ),
      );
      final result = await ForumClientAdapterFactory(
        config: blogConfig,
        network: network,
      ).createUserBlogDirectory().load(const UserBlogDirectoryQuery.public());
      expect(result.failureOrNull, isNull);
      final item = result.dataOrNull!.items.single;
      expect(item.title, '[Actual] title & punctuation');
      expect(item.categoryNames, ['Site category', 'Author category']);
      expect(() => item.categoryNames.clear(), throwsUnsupportedError);
      expect(network.requests, hasLength(1));
      final detail = await read('''
      <em>[<a href="home.php?mod=space&do=blog&view=all&catid=8">Site category</a>]</em>
      [Actual] title &amp; punctuation
    ''');
      expect(item.title, detail.title);
    },
  );

  test('plain brackets and unknown list markup remain title content', () async {
    for (final title in [
      '[Actual] title',
      '<span>Actual</span> title',
      'Title <span>[suffix]</span>',
    ]) {
      final network = BlogFixtureNetwork(
        blogFeed().replaceFirst('Title &amp; punctuation', title),
      );
      final result = await ForumClientAdapterFactory(
        config: blogConfig,
        network: network,
      ).createUserBlogDirectory().load(const UserBlogDirectoryQuery.public());
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.items.single.categoryNames, isEmpty);
      expect(result.dataOrNull!.items.single.title, isNotEmpty);
    }
  });
}
