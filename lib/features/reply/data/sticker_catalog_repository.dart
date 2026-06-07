import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/sticker_code_normalizer.dart';

abstract class StickerCatalogRepository {
  Future<List<StickerGroup>> loadStickerGroups();
}

class AssetStickerCatalogRepository implements StickerCatalogRepository {
  const AssetStickerCatalogRepository({
    required StickerCodeNormalizer normalizer,
    AssetBundle? bundle,
    this.assetPath = 'assets/stickers/stickers.json',
    this.assetRoot = 'assets/stickers',
  })  : _normalizer = normalizer,
        _bundle = bundle;

  final StickerCodeNormalizer _normalizer;
  final AssetBundle? _bundle;
  final String assetPath;
  final String assetRoot;

  @override
  Future<List<StickerGroup>> loadStickerGroups() async {
    final raw = await (_bundle ?? rootBundle).loadString(assetPath);
    final decoded = ParseUtils.asMap(jsonDecode(raw));
    final groups = ParseUtils.asList(decoded['smilies']);
    return groups.indexed.map((entry) {
      final (groupIndex, rawGroup) = entry;
      final metadata = _metadataForIndex(groupIndex);
      final stickers = ParseUtils.asList(rawGroup)
          .map(_parseSticker)
          .whereType<StickerItem>()
          .toList(growable: false);
      return StickerGroup(
        id: metadata.id,
        title: metadata.title,
        stickers: stickers,
      );
    }).toList(growable: false);
  }

  _StickerGroupMetadata _metadataForIndex(int index) {
    if (index >= 0 && index < _knownGroupMetadata.length) {
      return _knownGroupMetadata[index];
    }
    return _StickerGroupMetadata(
      id: 'group-$index',
      title: 'group-$index',
    );
  }

  StickerItem? _parseSticker(Object? rawSticker) {
    final map = ParseUtils.asMap(rawSticker);
    final rawCodePattern = ParseUtils.asString(map['code']).trim();
    final image = ParseUtils.asString(map['image']).trim();
    if (rawCodePattern.isEmpty || image.isEmpty) {
      return null;
    }
    return StickerItem(
      code: _normalizer.normalize(rawCodePattern),
      assetPath: '$assetRoot/$image',
      rawCodePattern: rawCodePattern,
    );
  }
}

const _knownGroupMetadata = <_StickerGroupMetadata>[
  _StickerGroupMetadata(id: 'default', title: '默认表情'),
  _StickerGroupMetadata(id: 'bugcat', title: '貓貓蟲'),
  _StickerGroupMetadata(id: 'coolmonkey', title: '企鹅表情'),
  _StickerGroupMetadata(id: 'gexing', title: '个性表情'),
  _StickerGroupMetadata(id: 'gexing2', title: '孤獨搖滾'),
  _StickerGroupMetadata(id: 'azukisan', title: '小豆泥'),
];

class _StickerGroupMetadata {
  const _StickerGroupMetadata({
    required this.id,
    required this.title,
  });

  final String id;
  final String title;
}
