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
      final stickers = ParseUtils.asList(rawGroup)
          .map(_parseSticker)
          .whereType<StickerItem>()
          .toList(growable: false);
      return StickerGroup(
        id: 'group-$groupIndex',
        title: 'group-$groupIndex',
        stickers: stickers,
      );
    }).toList(growable: false);
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
