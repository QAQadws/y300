import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

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

  test('forumDisplay snapshot key is stable and separates filter variants', () {
    const canonicalizer = CacheKeyCanonicalizer();

    final first = canonicalizer.forumDisplaySnapshot(
      fid: '30',
      page: 2,
      queryParameters: const <String, String>{
        'typeid': '69',
        'filter': 'typeid',
      },
    );
    final second = canonicalizer.forumDisplaySnapshot(
      fid: '30',
      page: 2,
      queryParameters: const <String, String>{
        'filter': 'typeid',
        'typeid': '69',
      },
    );
    final different = canonicalizer.forumDisplaySnapshot(
      fid: '30',
      page: 2,
      queryParameters: const <String, String>{'filter': 'digest'},
    );

    expect(first.cacheKey, second.cacheKey);
    expect(first.cacheKey, isNot(different.cacheKey));
    expect(first.snapshotType, CacheKeyCanonicalizer.forumDisplaySnapshotType);
  });

  test('forumHome document and snapshot keys share the home owner', () {
    const canonicalizer = CacheKeyCanonicalizer();

    final document = canonicalizer.forumHome();
    final snapshot = canonicalizer.forumHomeSnapshot();

    expect(document.ownerType, CacheOwnerType.forum);
    expect(document.ownerId, 'home');
    expect(document.sourceUrl, 'https://bbs.yamibo.com/index.php?mobile=2');
    expect(snapshot.ownerType, CacheOwnerType.forum);
    expect(snapshot.ownerId, 'home');
    expect(snapshot.snapshotType, CacheKeyCanonicalizer.forumHomeSnapshotType);
    expect(snapshot.sourceDocumentKey, document.cacheKey);
  });
}
