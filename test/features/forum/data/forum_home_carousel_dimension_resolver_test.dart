import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/forum/data/services/forum_home_carousel_dimension_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  group('ForumHomeCarouselDimensionResolver', () {
    test(
      'cold cache restores exact URL layout without querying SQLite',
      () async {
        final first = ForumHomeCarouselDimensionResolver(
          dimensionIndex: _FakeDimensionIndex(
            const ForumImageDimensions(
              width: 1200,
              height: 400,
              source: ForumImageDimensionSource.cacheMetadata,
            ),
          ),
        );
        const url = 'https://bbs.yamibo.com/banner.jpg';
        await first.resolveAspectRatio(url);
        final cold = ForumHomeCarouselDimensionResolver(
          dimensionIndex: _ThrowingDimensionIndex(),
        );
        expect(await cold.resolveCachedAspectRatio(url), 3);
        expect(await cold.resolveCachedAspectRatio('$url?new'), isNull);
      },
    );
    test('restores the current or latest home carousel dimensions', () async {
      final index = _FakeDimensionIndex(
        const ForumImageDimensions(
          width: 1200,
          height: 400,
          source: ForumImageDimensionSource.cacheMetadata,
        ),
      );
      final resolver = ForumHomeCarouselDimensionResolver(
        dimensionIndex: index,
      );

      final ratio = await resolver.resolveAspectRatio(
        'https://bbs.yamibo.com/banner.jpg',
      );

      expect(ratio, 3);
      expect(index.lastSpec?.ownerId, 'home');
      expect(index.lastSpec?.kind, ForumImageKind.forumHeadImage);
      expect(index.lastKnownCalls, 1);
    });

    test('returns null when no valid local dimensions exist', () async {
      final resolver = ForumHomeCarouselDimensionResolver(
        dimensionIndex: _FakeDimensionIndex(null),
      );

      expect(
        await resolver.resolveAspectRatio('https://bbs.yamibo.com/banner.jpg'),
        isNull,
      );
    });

    test('fails open for layout metadata lookup errors', () async {
      final resolver = ForumHomeCarouselDimensionResolver(
        dimensionIndex: _ThrowingDimensionIndex(),
      );

      expect(
        await resolver.resolveAspectRatio('https://bbs.yamibo.com/banner.jpg'),
        isNull,
      );
    });
  });
}

final class _FakeDimensionIndex implements ForumImageDimensionIndex {
  _FakeDimensionIndex(this.dimensions);

  final ForumImageDimensions? dimensions;
  int lastKnownCalls = 0;
  ForumImageLoadSpec? lastSpec;

  @override
  Future<ForumImageDimensions?> getBySpec(ForumImageLoadSpec spec) async =>
      dimensions;

  @override
  Future<ForumImageDimensions?> getLastKnownBySpec(
    ForumImageLoadSpec spec,
  ) async {
    lastKnownCalls += 1;
    lastSpec = spec;
    return dimensions;
  }

  @override
  Future<void> recordDecodedDimensions({
    required ForumImageLoadSpec spec,
    required Size size,
  }) async {}
}

final class _ThrowingDimensionIndex implements ForumImageDimensionIndex {
  @override
  Future<ForumImageDimensions?> getBySpec(ForumImageLoadSpec spec) {
    throw StateError('metadata unavailable');
  }

  @override
  Future<ForumImageDimensions?> getLastKnownBySpec(ForumImageLoadSpec spec) {
    throw StateError('metadata unavailable');
  }

  @override
  Future<void> recordDecodedDimensions({
    required ForumImageLoadSpec spec,
    required Size size,
  }) async {}
}
