/// Read and persistence contracts for the ordered Discuz sticker catalog.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';

/// Query parameters for forum sticker catalog.
final class ForumStickerCatalogQuery {
  /// Creates a [ForumStickerCatalogQuery].
  const ForumStickerCatalogQuery({this.forceRefresh = false});

  /// Force refresh.
  final bool forceRefresh;
}

/// Source-neutral forum sticker item.
final class ForumStickerItem {
  /// Creates a [ForumStickerItem].
  const ForumStickerItem({
    required this.rawCodePattern,
    required this.insertionCode,
    required this.imagePath,
    required this.imageUri,
  });

  /// Raw code pattern.
  final String rawCodePattern;

  /// Insertion code.
  final String insertionCode;

  /// Image path.
  final String imagePath;

  /// Image uri.
  final Uri imageUri;
}

/// Source-neutral forum sticker group.
final class ForumStickerGroup {
  /// Creates a [ForumStickerGroup].
  const ForumStickerGroup({required this.id, required this.items});

  /// Stable source group identifier.
  final String id;

  /// Items.
  final List<ForumStickerItem> items;
}

/// Source-neutral forum sticker catalog data.
final class ForumStickerCatalogData {
  /// Creates a [ForumStickerCatalogData].
  const ForumStickerCatalogData({
    required this.groups,
    required this.refreshed,
  });

  /// Groups.
  final List<ForumStickerGroup> groups;

  /// Refreshed.
  final bool refreshed;
}

/// Capabilities exposed by forum sticker catalog.
enum ForumStickerCatalogCapability {
  /// Stable group identity.
  stableGroupIdentity,

  /// Ordered groups.
  orderedGroups,

  /// Ordered items.
  orderedItems,

  /// Normalized insertion code.
  normalizedInsertionCode,

  /// Image reference.
  imageReference,
}

/// Capabilities declared by the forum sticker catalog source.
final class ForumStickerCatalogSourceCapabilities {
  /// Creates a [ForumStickerCatalogSourceCapabilities].
  const ForumStickerCatalogSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumStickerCatalogCapability> values;

  /// Converts this value to read capabilities.
  ForumStickerCatalogReadCapabilities toReadCapabilities() =>
      ForumStickerCatalogReadCapabilities(values: values);
}

/// Capabilities effective for one forum sticker catalog read.
final class ForumStickerCatalogReadCapabilities {
  /// Creates a [ForumStickerCatalogReadCapabilities].
  const ForumStickerCatalogReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumStickerCatalogCapability> values;
}

/// Source-neutral forum sticker catalog store.
abstract interface class ForumStickerCatalogStore {
  /// Reads the encoded sticker catalog, or null when absent.
  Future<String?> read();

  /// Atomically stores the encoded sticker catalog.
  Future<void> write(String encoded);

  /// Removes the encoded sticker catalog.
  Future<void> clear();
}

/// Ephemeral sticker catalog store for tests and non-production tools.
final class MemoryForumStickerCatalogStore implements ForumStickerCatalogStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String encoded) async => _value = encoded;

  @override
  Future<void> clear() async => _value = null;
}

/// Loads forum sticker catalog data through a source-neutral contract.
abstract interface class ForumStickerCatalogRepository {
  /// Capabilities declared by this source.
  ForumStickerCatalogSourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<
    DataReadResult<ForumStickerCatalogData, ForumStickerCatalogReadCapabilities>
  >
  load(
    ForumStickerCatalogQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
