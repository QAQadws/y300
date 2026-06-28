import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/composer_shared/data/repositories/sticker_catalog_repository.dart';
import 'package:y300/features/composer_shared/domain/services/sticker_code_normalizer.dart';

void main() {
  group('RemoteStickerCatalogRepository', () {
    test(
      'loads sticker groups from remote payload using image directory ids',
      () async {
        final cache = _MemoryStickerCatalogCacheStore();
        final repository = RemoteStickerCatalogRepository(
          remoteDataSource: _FakeStickerCatalogRemoteDataSource(_payload()),
          cacheStore: cache,
          normalizer: const StickerCodeNormalizer(),
        );

        final groups = await repository.loadStickerGroups();

        expect(groups.map((group) => group.id), <String>[
          'default',
          'bugcat',
          'newgroup',
        ]);
        expect(groups.map((group) => group.title), <String>[
          '默认表情',
          '貓貓蟲',
          'newgroup',
        ]);
        expect(groups.first.stickers.first.code, '{:1_1000:}');
        expect(groups.first.stickers.first.imagePath, 'default/handshake.gif');
        expect(
          groups.first.stickers.first.imageUrl,
          'https://bbs.yamibo.com/static/image/smiley/default/handshake.gif',
        );
        expect(
          groups.first.stickers.first.cacheKey,
          ImageCacheKeys.remoteSmiley('default/handshake.gif'),
        );
        expect(cache.saved, isNotNull);
      },
    );

    test('uses fresh cached catalog without remote fetch', () async {
      final remote = _FakeStickerCatalogRemoteDataSource(
        _payload(code: r'/\{\:9_999\:\}/'),
      );
      final cache = _MemoryStickerCatalogCacheStore()
        ..stored = CachedStickerCatalog(
          raw: _payload(),
          fetchedAt: DateTime.now(),
          module: 'smiley',
          version: '4',
          payloadHash: 'cached',
        );
      final repository = RemoteStickerCatalogRepository(
        remoteDataSource: remote,
        cacheStore: cache,
        normalizer: const StickerCodeNormalizer(),
      );

      final groups = await repository.loadStickerGroups();

      expect(remote.fetchCount, 0);
      expect(groups.first.stickers.first.code, '{:1_1000:}');
    });

    test('falls back to stale cache when refresh fails', () async {
      final cache = _MemoryStickerCatalogCacheStore()
        ..stored = CachedStickerCatalog(
          raw: _payload(),
          fetchedAt: DateTime(2020),
          module: 'smiley',
          version: '4',
          payloadHash: 'stale',
        );
      final repository = RemoteStickerCatalogRepository(
        remoteDataSource: _ThrowingStickerCatalogRemoteDataSource(),
        cacheStore: cache,
        normalizer: const StickerCodeNormalizer(),
        freshFor: const Duration(days: 1),
      );

      final groups = await repository.loadStickerGroups();

      expect(groups.first.stickers.first.code, '{:1_1000:}');
    });
  });
}

Map<String, Object?> _payload({String code = r'/\{\:1_1000\:\}/'}) {
  return <String, Object?>{
    'Variables': <String, Object?>{
      'smilies': <Object?>[
        <Object?>[
          <String, String>{'code': code, 'image': 'default/handshake.gif'},
        ],
        <Object?>[
          <String, String>{
            'code': r'/\{\:9_656\:\}/',
            'image': 'bugcat/Capoo16.gif',
          },
        ],
        <Object?>[
          <String, String>{
            'code': r'/\{\:99_1\:\}/',
            'image': 'newgroup/new.gif',
          },
        ],
      ],
    },
  };
}

class _FakeStickerCatalogRemoteDataSource
    implements StickerCatalogRemoteDataSource {
  _FakeStickerCatalogRemoteDataSource(this.payload);

  final Map<String, Object?> payload;
  int fetchCount = 0;

  @override
  Future<StickerCatalogPayload> fetch() async {
    fetchCount += 1;
    return StickerCatalogPayload(
      raw: payload,
      fetchedAt: DateTime.now(),
      module: 'smiley',
      version: '4',
    );
  }
}

class _ThrowingStickerCatalogRemoteDataSource
    implements StickerCatalogRemoteDataSource {
  @override
  Future<StickerCatalogPayload> fetch() {
    throw StateError('offline');
  }
}

class _MemoryStickerCatalogCacheStore implements StickerCatalogCacheStore {
  CachedStickerCatalog? stored;
  CachedStickerCatalog? saved;

  @override
  Future<void> clear() async {
    stored = null;
  }

  @override
  Future<CachedStickerCatalog?> load() async => stored;

  @override
  Future<void> save(CachedStickerCatalog catalog) async {
    saved = catalog;
    stored = catalog;
  }
}
