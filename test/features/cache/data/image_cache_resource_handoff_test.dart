import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/services/image_cache_resource_handoff.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';

void main() {
  test('handoff is exact, single-use and records display access once', () {
    var accesses = 0;
    final handoff = ValidatedImageCacheResourceHandoff(
      request: _request(),
      result: _result,
      isCurrent: () => true,
      recordAccess: () => accesses++,
    );
    expect(handoff.take(_request()), same(_result));
    expect(handoff.take(_request()), isNull);
    expect(accesses, 1);
  });

  for (final next in [
    _request(owner: 'other'),
    _request(source: 'https://example.invalid/new.png'),
  ]) {
    test(
      'a different owner or source cannot consume a validated file: ${next.ownerId}/${next.sourceUrl}',
      () {
        final handoff = ValidatedImageCacheResourceHandoff(
          request: _request(),
          result: _result,
          isCurrent: () => true,
          recordAccess: () => fail('must not record a rejected access'),
        );
        expect(handoff.take(next), isNull);
      },
    );
  }

  test(
    'expiration and invalidation reject a handoff without touching the file',
    () {
      var elapsed = Duration.zero;
      var current = true;
      ValidatedImageCacheResourceHandoff create() =>
          ValidatedImageCacheResourceHandoff(
            request: _request(),
            result: _result,
            isCurrent: () => current,
            elapsed: () => elapsed,
            recordAccess: () => fail('must not record rejected access'),
          );
      final expired = create();
      elapsed = const Duration(seconds: 2);
      expect(expired.take(_request()), isNull);
      final retired = create();
      current = false;
      expect(retired.take(_request()), isNull);
      current = true;
      final failed = create()..invalidate();
      expect(failed.take(_request()), isNull);
    },
  );
}

ImageCacheRequest _request({
  String owner = 'owner',
  String source = 'https://example.invalid/image.png',
}) => ImageCacheRequest(
  cacheKey: 'key',
  sourceUrl: source,
  ownerType: ImageCacheOwnerType.thread,
  ownerId: owner,
  role: ImageCacheRole.threadInline,
);
const _result = CachedImageResult(
  success: true,
  cacheKey: 'key',
  localPath: '/synthetic/image.png',
);
