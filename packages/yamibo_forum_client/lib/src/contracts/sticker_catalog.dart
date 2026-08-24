import 'cache_load_policy.dart';
import 'data_read_contract.dart';

final class ForumStickerCatalogQuery {
  const ForumStickerCatalogQuery({this.forceRefresh = false});
  final bool forceRefresh;
}

final class ForumStickerItem {
  const ForumStickerItem({
    required this.rawCodePattern,
    required this.insertionCode,
    required this.imagePath,
    required this.imageUri,
  });
  final String rawCodePattern;
  final String insertionCode;
  final String imagePath;
  final Uri imageUri;
}

final class ForumStickerGroup {
  const ForumStickerGroup({required this.id, required this.items});
  final String id;
  final List<ForumStickerItem> items;
}

final class ForumStickerCatalogData {
  const ForumStickerCatalogData({
    required this.groups,
    required this.refreshed,
  });
  final List<ForumStickerGroup> groups;
  final bool refreshed;
}

enum ForumStickerCatalogCapability {
  stableGroupIdentity,
  orderedGroups,
  orderedItems,
  normalizedInsertionCode,
  imageReference,
}

final class ForumStickerCatalogSourceCapabilities {
  const ForumStickerCatalogSourceCapabilities({required this.values});
  final DataCapabilitySet<ForumStickerCatalogCapability> values;
  ForumStickerCatalogReadCapabilities toReadCapabilities() =>
      ForumStickerCatalogReadCapabilities(values: values);
}

final class ForumStickerCatalogReadCapabilities {
  const ForumStickerCatalogReadCapabilities({required this.values});
  final DataCapabilitySet<ForumStickerCatalogCapability> values;
}

abstract interface class ForumStickerCatalogStore {
  Future<String?> read();
  Future<void> write(String encoded);
  Future<void> clear();
}

abstract interface class ForumStickerCatalogRepository {
  ForumStickerCatalogSourceCapabilities get capabilities;
  Future<
    DataReadResult<ForumStickerCatalogData, ForumStickerCatalogReadCapabilities>
  >
  load(
    ForumStickerCatalogQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
