import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reply/data/sticker_catalog_repository.dart';
import 'package:y300/features/reply/domain/services/sticker_code_normalizer.dart';

void main() {
  group('AssetStickerCatalogRepository', () {
    test('loads sticker groups from asset json', () async {
      final repository = AssetStickerCatalogRepository(
        normalizer: const StickerCodeNormalizer(),
        bundle: _FakeAssetBundle(
          <String, String>{
            'assets/stickers/stickers.json': jsonEncode(
              <String, Object?>{
                'smilies': <Object?>[
                  <Object?>[
                    <String, String>{
                      'code': r'/\{\:9_656\:\}/',
                      'image': 'bugcat/Capoo16.gif',
                    },
                    <String, String>{
                      'code': r'/\{\:9_657\:\}/',
                      'image': 'bugcat/Capoo27.gif',
                    },
                  ],
                  <Object?>[
                    <String, String>{
                      'code': r'/\{\:1_1000\:\}/',
                      'image': 'default/handshake.gif',
                    },
                  ],
                ],
              },
            ),
          },
        ),
      );

      final groups = await repository.loadStickerGroups();

      expect(groups, hasLength(2));
      expect(groups[0].id, 'group-0');
      expect(groups[0].title, 'group-0');
      expect(groups[0].stickers, hasLength(2));
      expect(groups[0].stickers.first.code, '{:9_656:}');
      expect(
        groups[0].stickers.first.assetPath,
        'assets/stickers/bugcat/Capoo16.gif',
      );
      expect(groups[1].stickers.single.code, '{:1_1000:}');
      expect(
        groups[1].stickers.single.assetPath,
        'assets/stickers/default/handshake.gif',
      );
    });

    test('loads Discuz sticker json with raw escaped code patterns', () async {
      final repository = AssetStickerCatalogRepository(
        normalizer: const StickerCodeNormalizer(),
        bundle: _FakeAssetBundle(
          <String, String>{
            'assets/stickers/stickers.json': r'''
{
  "smilies": [
    [
      {
        "code":"/\{\:9_656\:\}/",
        "image": "bugcat/Capoo16.gif"
      }
    ]
  ]
}
''',
          },
        ),
      );

      final groups = await repository.loadStickerGroups();

      expect(groups, hasLength(1));
      expect(groups.single.stickers.single.code, '{:9_656:}');
      expect(
        groups.single.stickers.single.assetPath,
        'assets/stickers/bugcat/Capoo16.gif',
      );
    });

    test('keeps all six sticker groups from asset payload', () async {
      final repository = AssetStickerCatalogRepository(
        normalizer: const StickerCodeNormalizer(),
        bundle: _FakeAssetBundle(
          <String, String>{
            'assets/stickers/stickers.json': r'''
{
  "smilies": [
    [{"code":"/\{\:0_1000\:\}/","image":"group0/item.gif"}],
    [{"code":"/\{\:1_1000\:\}/","image":"group1/item.gif"}],
    [{"code":"/\{\:2_1000\:\}/","image":"group2/item.gif"}],
    [{"code":"/\{\:3_1000\:\}/","image":"group3/item.gif"}],
    [{"code":"/\{\:4_1000\:\}/","image":"group4/item.gif"}],
    [{"code":"/\{\:5_1000\:\}/","image":"group5/item.gif"}]
  ]
}
''',
          },
        ),
      );

      final groups = await repository.loadStickerGroups();

      expect(groups, hasLength(6));
      expect(groups.map((group) => group.id), [
        'group-0',
        'group-1',
        'group-2',
        'group-3',
        'group-4',
        'group-5',
      ]);
    });

    test('skips sticker entries with missing code or image', () async {
      final repository = AssetStickerCatalogRepository(
        normalizer: const StickerCodeNormalizer(),
        bundle: _FakeAssetBundle(
          <String, String>{
            'assets/stickers/stickers.json': jsonEncode(
              <String, Object?>{
                'smilies': <Object?>[
                  <Object?>[
                    <String, String>{
                      'code': r'/\{\:9_656\:\}/',
                      'image': 'bugcat/Capoo16.gif',
                    },
                    <String, String>{'code': r'/\{\:9_657\:\}/'},
                    <String, String>{'image': 'bugcat/Capoo27.gif'},
                  ],
                ],
              },
            ),
          },
        ),
      );

      final groups = await repository.loadStickerGroups();

      expect(groups, hasLength(1));
      expect(groups.single.stickers, hasLength(1));
      expect(groups.single.stickers.single.code, '{:9_656:}');
    });
  });
}

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) {
      throw StateError('Missing test asset: $key');
    }
    final bytes = utf8.encode(value);
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
