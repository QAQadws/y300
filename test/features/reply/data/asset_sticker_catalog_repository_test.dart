import 'dart:convert';
import 'dart:io';

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
                      'code': '{:1_1000:}',
                      'image': 'default/handshake.gif',
                    },
                    <String, String>{
                      'code': '{:1_1001:}',
                      'image': 'default/6.png',
                    },
                  ],
                  <Object?>[
                    <String, String>{
                      'code': '{:9_656:}',
                      'image': 'bugcat/Capoo16.gif',
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
      expect(groups[0].id, 'default');
      expect(groups[0].title, '默认表情');
      expect(groups[0].stickers, hasLength(2));
      expect(groups[0].stickers.first.code, '{:1_1000:}');
      expect(groups[0].stickers.first.rawCodePattern, '{:1_1000:}');
      expect(
        groups[0].stickers.first.assetPath,
        'assets/stickers/default/handshake.gif',
      );
      expect(groups[1].id, 'bugcat');
      expect(groups[1].title, '貓貓蟲');
      expect(groups[1].stickers.single.code, '{:9_656:}');
      expect(
        groups[1].stickers.single.assetPath,
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
    [{"code":"{:0_1000:}","image":"group0/item.gif"}],
    [{"code":"{:1_1000:}","image":"group1/item.gif"}],
    [{"code":"{:2_1000:}","image":"group2/item.gif"}],
    [{"code":"{:3_1000:}","image":"group3/item.gif"}],
    [{"code":"{:4_1000:}","image":"group4/item.gif"}],
    [{"code":"{:5_1000:}","image":"group5/item.gif"}]
  ]
}
''',
          },
        ),
      );

      final groups = await repository.loadStickerGroups();

      expect(groups, hasLength(6));
      expect(groups.map((group) => group.id), [
        'default',
        'bugcat',
        'coolmonkey',
        'gexing',
        'gexing2',
        'azukisan',
      ]);
      expect(groups.map((group) => group.title), [
        '默认表情',
        '貓貓蟲',
        '企鹅表情',
        '个性表情',
        '孤獨搖滾',
        '小豆泥',
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
                      'code': '{:9_656:}',
                      'image': 'bugcat/Capoo16.gif',
                    },
                    <String, String>{'code': '{:9_657:}'},
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

    test('real sticker json images point to existing asset files', () async {
      final raw = await File('assets/stickers/stickers.json').readAsString();
      final decoded = jsonDecode(raw);
      expect(decoded, isA<Map<String, Object?>>());
      final smilies = (decoded as Map<String, Object?>)['smilies'];
      expect(smilies, isA<List<Object?>>());

      final missingImages = <String>[];
      var imageCount = 0;
      for (final group in smilies as List<Object?>) {
        expect(group, isA<List<Object?>>());
        for (final rawSticker in group as List<Object?>) {
          expect(rawSticker, isA<Map<String, Object?>>());
          final sticker = rawSticker as Map<String, Object?>;
          final image = sticker['image'];
          expect(image, isA<String>());
          final imagePath = 'assets/stickers/$image';
          imageCount += 1;
          if (!File(imagePath).existsSync()) {
            missingImages.add(imagePath);
          }
        }
      }

      expect(imageCount, greaterThan(0));
      expect(missingImages, isEmpty);
    });

    test('pubspec declares sticker image asset directories', () async {
      final pubspec = await File('pubspec.yaml').readAsString();

      expect(pubspec, contains('- assets/stickers/default/'));
      expect(pubspec, contains('- assets/stickers/bugcat/'));
      expect(pubspec, contains('- assets/stickers/coolmonkey/'));
      expect(pubspec, contains('- assets/stickers/gexing/'));
      expect(pubspec, contains('- assets/stickers/gexing2/'));
      expect(pubspec, contains('- assets/stickers/azukisan/'));
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
