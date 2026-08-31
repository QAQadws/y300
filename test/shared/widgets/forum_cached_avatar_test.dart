import 'package:flutter/material.dart';
import '../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

void main() {
  testWidgets('uses a background-derived surface for unavailable avatars', (
    tester,
  ) async {
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
                  'https://bbs.yamibo.com/uc_server/data/avatar/custom.svg',
              ownerId: '2',
              ownerType: ImageCacheOwnerType.profile,
              size: 32,
            ),
          ],
        ),
      ),
    );

    expect(find.byType(CachedLibraryImage), findsNothing);
    expect(find.byType(Image), findsNothing);
    final placeholders = tester.widgetList<ColoredBox>(
      find.byKey(const Key('forum-avatar-placeholder')),
    );
    expect(placeholders, hasLength(2));
    final context = tester.element(find.byType(ForumCachedAvatar).first);
    final background = Theme.of(context).scaffoldBackgroundColor;
    expect(
      placeholders.map((placeholder) => placeholder.color),
      everyElement(ForumCachedAvatar.placeholderColorFor(background)),
    );
  });

  testWidgets('renders the known forum default avatar from the local asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ForumCachedAvatar(
          imageUrl: 'https://bbs.yamibo.com/uc_server/data/avatar/noavatar.svg',
          ownerId: '2',
          ownerType: ImageCacheOwnerType.profile,
          size: 32,
        ),
      ),
    );

    final image = tester.widget<CachedLibraryImage>(
      find.byType(CachedLibraryImage),
    );
    expect(image.request, isNull);
    expect(
      image.imageProviderOverride,
      isA<AssetImage>().having(
        (provider) => provider.assetName,
        'assetName',
        forumDefaultAvatarAsset,
      ),
    );
    expect(image.fadeInDuration, const Duration(milliseconds: 300));
  });

  testWidgets('can use the local default avatar for an unavailable source', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ForumCachedAvatar(
          imageUrl: '',
          ownerId: '2',
          ownerType: ImageCacheOwnerType.profile,
          size: 32,
          fallbackPolicy: ForumAvatarFallbackPolicy.localDefaultAvatar,
        ),
      ),
    );

    final image = tester.widget<CachedLibraryImage>(
      find.byType(CachedLibraryImage),
    );
    expect(image.request, isNull);
    expect(
      image.imageProviderOverride,
      isA<AssetImage>().having(
        (provider) => provider.assetName,
        'assetName',
        forumDefaultAvatarAsset,
      ),
    );
    expect(image.placeholder, isA<ColoredBox>());
    expect(image.fadeInDuration, ForumCachedAvatar.fadeInDuration);
  });

  testWidgets('can fall back to the local default after a network failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ForumCachedAvatar(
          imageUrl:
              'https://bbs.yamibo.com/uc_server/data/avatar/000/00/00/42_avatar_middle.jpg',
          ownerId: '42',
          ownerType: ImageCacheOwnerType.thread,
          size: 34,
          fallbackPolicy: ForumAvatarFallbackPolicy.localDefaultAvatar,
        ),
      ),
    );

    final remote = tester.widget<CachedLibraryImage>(
      find.byType(CachedLibraryImage),
    );
    final localDefault = remote.errorPlaceholder as CachedLibraryImage;
    expect(localDefault.request, isNull);
    expect(
      localDefault.imageProviderOverride,
      isA<AssetImage>().having(
        (provider) => provider.assetName,
        'assetName',
        forumDefaultAvatarAsset,
      ),
    );
    expect(localDefault.placeholder, isA<ColoredBox>());
    expect(localDefault.fadeInDuration, ForumCachedAvatar.fadeInDuration);
  });

  testWidgets(
    'slightly darkens the active theme background without decoration',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          Theme(
            data: ThemeData.dark(),
            child: const ForumCachedAvatar(
              imageUrl: '',
              ownerId: '1',
              ownerType: ImageCacheOwnerType.profile,
              size: 32,
            ),
          ),
        ),
      );

      final placeholder = tester.widget<ColoredBox>(
        find.byKey(const Key('forum-avatar-placeholder')),
      );
      final context = tester.element(find.byType(ForumCachedAvatar));
      final background = Theme.of(context).scaffoldBackgroundColor;
      expect(
        placeholder.color,
        ForumCachedAvatar.placeholderColorFor(background),
      );
      expect(placeholder.color, isNot(Colors.black));
      expect(placeholder.color, isNot(background));
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person), findsNothing);
      expect(find.text('?'), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.byType(ClipOval), findsOneWidget);
      expect(
        tester.getSize(find.byType(ForumCachedAvatar)),
        const Size.square(32),
      );
    },
  );

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
    final context = tester.element(find.byType(ForumCachedAvatar));
    final background = Theme.of(context).scaffoldBackgroundColor;
    expect(image.placeholder, isA<ColoredBox>());
    expect(
      (image.placeholder as ColoredBox).color,
      ForumCachedAvatar.placeholderColorFor(background),
    );
    expect(image.errorPlaceholder, same(image.placeholder));
    expect(image.fadeInDuration, ForumCachedAvatar.fadeInDuration);
    expect(image.fadeInDuration, const Duration(milliseconds: 300));
  });
}

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
      forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
    ],
    child: LocalizedTestApp(home: Scaffold(body: child)),
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
