import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/cache_key_canonicalizer.dart';

void main() {
  test('threadDetail canonical key is stable for sorted query parameters', () {
    const canonicalizer = CacheKeyCanonicalizer();

    final first = canonicalizer.threadDetail(
      tid: '560713',
      page: 2,
      queryParameters: const <String, String>{
        'ordertype': '1',
        'authorid': '448216',
      },
    );
    final second = canonicalizer.threadDetail(
      tid: '560713',
      page: 2,
      queryParameters: const <String, String>{
        'authorid': '448216',
        'ordertype': '1',
      },
    );

    expect(first.cacheKey, second.cacheKey);
    expect(first.sourceUrl, second.sourceUrl);
    expect(first.sourceUrl, contains('authorid=448216'));
    expect(first.sourceUrl, contains('ordertype=1'));
  });

  test('threadDetail separates author and order variants', () {
    const canonicalizer = CacheKeyCanonicalizer();

    final allPosts = canonicalizer.threadDetail(tid: '560713', page: 1);
    final authorOnly = canonicalizer.threadDetail(
      tid: '560713',
      page: 1,
      queryParameters: const <String, String>{'authorid': '448216'},
    );
    final reverseOrder = canonicalizer.threadDetail(
      tid: '560713',
      page: 1,
      queryParameters: const <String, String>{'ordertype': '1'},
    );

    expect(allPosts.cacheKey, isNot(authorOnly.cacheKey));
    expect(allPosts.cacheKey, isNot(reverseOrder.cacheKey));
    expect(authorOnly.cacheKey, isNot(reverseOrder.cacheKey));
  });
}
