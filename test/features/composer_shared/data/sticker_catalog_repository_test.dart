import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    as forum;
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/composer_shared/data/repositories/sticker_catalog_repository.dart';

void main() {
  group('PackageStickerCatalogRepository', () {
    test('projects the package catalog into composer sticker models', () async {
      final source = _FakeStickerCatalogRepository(_success(refreshed: false));
      final repository = PackageStickerCatalogRepository(repository: source);

      final groups = await repository.loadStickerGroups();

      expect(source.queries.single.forceRefresh, isFalse);
      expect(groups.single.id, 'default');
      expect(groups.single.title, '默认表情');
      final sticker = groups.single.stickers.single;
      expect(sticker.code, '{:1_1000:}');
      expect(sticker.rawCodePattern, r'/\{\:1_1000\:\}/');
      expect(sticker.imagePath, 'default/handshake.gif');
      expect(
        sticker.imageUrl,
        'https://bbs.yamibo.com/static/image/smiley/default/handshake.gif',
      );
      expect(
        sticker.cacheKey,
        ImageCacheKeys.remoteSmiley('default/handshake.gif'),
      );
    });

    test('forces a network refresh through the package contract', () async {
      final source = _FakeStickerCatalogRepository(_success(refreshed: true));
      final repository = PackageStickerCatalogRepository(repository: source);

      final result = await repository.refreshStickerGroups();

      expect(result.refreshed, isTrue);
      expect(source.queries.single.forceRefresh, isTrue);
      expect(source.policies.single, forum.CacheLoadPolicy.networkFirst);
    });

    test('does not disguise a package failure as an empty catalog', () async {
      final source = _FakeStickerCatalogRepository(
        const forum.DataReadFailure(
          kind: forum.DataReadFailureKind.network,
          diagnosticMessage: 'offline',
        ),
      );
      final repository = PackageStickerCatalogRepository(repository: source);

      await expectLater(repository.loadStickerGroups(), throwsStateError);
    });
  });
}

forum.DataReadResult<
  forum.ForumStickerCatalogData,
  forum.ForumStickerCatalogReadCapabilities
>
_success({required bool refreshed}) => forum.DataReadSuccess(
  data: forum.ForumStickerCatalogData(
    refreshed: refreshed,
    groups: [
      forum.ForumStickerGroup(
        id: 'default',
        items: [
          forum.ForumStickerItem(
            rawCodePattern: r'/\{\:1_1000\:\}/',
            insertionCode: '{:1_1000:}',
            imagePath: 'default/handshake.gif',
            imageUri: Uri.parse(
              'https://bbs.yamibo.com/static/image/smiley/default/handshake.gif',
            ),
          ),
        ],
      ),
    ],
  ),
  capabilities: forum.ForumStickerCatalogReadCapabilities(
    values: forum.DataCapabilitySet.supported(
      forum.ForumStickerCatalogCapability.values,
    ),
  ),
  metadata: const forum.DataReadMetadata.network(),
);

final class _FakeStickerCatalogRepository
    implements forum.ForumStickerCatalogRepository {
  _FakeStickerCatalogRepository(this.result);

  final forum.DataReadResult<
    forum.ForumStickerCatalogData,
    forum.ForumStickerCatalogReadCapabilities
  >
  result;
  final queries = <forum.ForumStickerCatalogQuery>[];
  final policies = <forum.CacheLoadPolicy>[];

  @override
  forum.ForumStickerCatalogSourceCapabilities get capabilities =>
      forum.ForumStickerCatalogSourceCapabilities(
        values: forum.DataCapabilitySet.supported(
          forum.ForumStickerCatalogCapability.values,
        ),
      );

  @override
  Future<
    forum.DataReadResult<
      forum.ForumStickerCatalogData,
      forum.ForumStickerCatalogReadCapabilities
    >
  >
  load(
    forum.ForumStickerCatalogQuery query, {
    forum.CacheLoadPolicy cachePolicy = forum.CacheLoadPolicy.cacheFirst,
  }) async {
    queries.add(query);
    policies.add(cachePolicy);
    return result;
  }
}
