import '../cache/forum_cache.dart';
import '../contracts/sticker_catalog.dart';

/// Persistent cache ports used by the standard third-party client runtime.
///
/// These stores contain reproducible forum documents and parsed snapshots.
/// Protected image files are intentionally not included because image cache
/// ownership, eviction, and decoding remain host responsibilities.
final class ForumClientCachePorts {
  /// Creates a complete set of persistent cache ports.
  const ForumClientCachePorts({
    required this.documents,
    required this.snapshots,
    required this.stickers,
  });

  /// Creates ephemeral cache ports for tests and short-lived tools.
  ///
  /// Production applications should provide persistent stores instead.
  factory ForumClientCachePorts.memory() => ForumClientCachePorts(
    documents: MemoryForumDocumentStore(),
    snapshots: MemoryForumSnapshotStore(),
    stickers: MemoryForumStickerCatalogStore(),
  );

  /// Stores source documents used by HTML-first adapters and stale fallback.
  final ForumDocumentStore documents;

  /// Stores decoded, versioned snapshots derived from source documents.
  final ForumSnapshotStore snapshots;

  /// Stores the encoded Discuz sticker catalog.
  final ForumStickerCatalogStore stickers;
}
