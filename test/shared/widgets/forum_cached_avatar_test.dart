import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

void main() {
  testWidgets('uses fallback for blank and svg avatar urls', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            ForumCachedAvatar(
              imageUrl: '',
              ownerId: '1',
              ownerType: ImageCacheOwnerType.profile,
              size: 32,
            ),
            ForumCachedAvatar(
              imageUrl:
                  'https://bbs.yamibo.com/uc_server/data/avatar/noavatar.svg',
              ownerId: '2',
              ownerType: ImageCacheOwnerType.profile,
              size: 32,
            ),
          ],
        ),
      ),
    );

    expect(find.byType(CachedLibraryImage), findsNothing);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('builds avatar cache request for network avatar', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ForumCachedAvatar(
          imageUrl:
              'https://bbs.yamibo.com/uc_server/data/avatar/000/00/00/42_avatar_middle.jpg',
          ownerId: '42',
          ownerType: ImageCacheOwnerType.thread,
          size: 34,
        ),
      ),
    );

    final image = tester.widget<CachedLibraryImage>(
      find.byType(CachedLibraryImage),
    );
    expect(image.request?.role, ImageCacheRole.avatar);
    expect(image.request?.ownerType, ImageCacheOwnerType.thread);
    expect(image.request?.ownerId, '42');
    expect(
      image.request?.effectiveRetentionClass,
      ImageRetentionClass.ephemeral,
    );
  });
}

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
      imageRequestHeaderBuilderProvider.overrideWithValue(
        const _StaticImageRequestHeaderBuilder(),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

class _NoopImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
}

class _StaticImageRequestHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageRequestHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{};
  }
}
