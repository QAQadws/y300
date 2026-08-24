import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  const origin = 'https://bbs.example.test';
  final canonicalizer = ForumCacheKeyCanonicalizer(
    siteOrigin: Uri.parse(origin),
  );

  test('forum home keeps the established cache identity', () {
    final descriptor = canonicalizer.forumHome();
    expect(
      descriptor.cacheKey,
      'document|forum|home|logged_in|$origin/index.php?mobile=2',
    );
    expect(
      canonicalizer.forumHomeSnapshot().cacheKey,
      'snapshot|forum|home|logged_in|$origin/index.php?mobile=2',
    );
  });

  test('thread variants and query order are canonical', () {
    final descriptor = canonicalizer.threadDetail(
      tid: '42',
      page: 2,
      queryParameters: const {'ordertype': '1', 'authorid': '7'},
    );
    expect(descriptor.ownerId, 'tid=42&page=2&authorid=7&ordertype=1');
    expect(
      descriptor.sourceUri.queryParameters.keys,
      orderedEquals(['authorid', 'mobile', 'mod', 'ordertype', 'page', 'tid']),
    );
  });
}
