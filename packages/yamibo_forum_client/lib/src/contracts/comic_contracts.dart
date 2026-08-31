/// Source-neutral comic episode catalog and discovery contracts.
library;

import 'data_read_contract.dart';

/// Values describing comic episode image origin.
enum ComicEpisodeImageOrigin {
  /// Image discovered from post-body DOM markup.
  dom,

  /// Image projected from structured attachment metadata.
  attachment,
}

/// Validated request for comic episode catalog.
final class ComicEpisodeCatalogRequest {
  /// Creates a [ComicEpisodeCatalogRequest].
  const ComicEpisodeCatalogRequest({required this.sourceTid});

  /// Stable source thread identifier.
  final String sourceTid;
}

/// Source-neutral comic episode image reference.
final class ComicEpisodeImageReference {
  /// Creates a [ComicEpisodeImageReference].
  const ComicEpisodeImageReference({
    required this.url,
    required this.origin,
    this.attachmentId,
  });

  /// Source-provided URL after validation.
  final String url;

  /// Origin reported for this value.
  final ComicEpisodeImageOrigin origin;

  /// Stable attachment identifier when available.
  final String? attachmentId;
}

/// Source-neutral comic episode image catalog.
final class ComicEpisodeImageCatalog {
  /// Creates a [ComicEpisodeImageCatalog].
  const ComicEpisodeImageCatalog({
    required this.sourceTid,
    required this.images,
  });

  /// Stable source thread identifier.
  final String sourceTid;

  /// Images in source order.
  final List<ComicEpisodeImageReference> images;
}

/// Capabilities exposed by comic episode catalog.
enum ComicEpisodeCatalogCapability {
  /// Stable source identity.
  stableSourceIdentity,

  /// Reliable first post identity.
  reliableFirstPostIdentity,

  /// Reliable image order.
  reliableImageOrder,

  /// Image origin.
  imageOrigin,

  /// Attachment id.
  attachmentId,
}

/// Capabilities declared by the comic episode catalog source.
final class ComicEpisodeCatalogSourceCapabilities {
  /// Creates a [ComicEpisodeCatalogSourceCapabilities].
  const ComicEpisodeCatalogSourceCapabilities(this.values);

  /// Per-capability support values.
  final DataCapabilitySet<ComicEpisodeCatalogCapability> values;

  /// Whether the requested capability is supported.
  bool supports(ComicEpisodeCatalogCapability capability) =>
      values.supports(capability);

  /// Converts this value to read capabilities.
  ComicEpisodeCatalogCapabilities toReadCapabilities() =>
      ComicEpisodeCatalogCapabilities(values);
}

/// Capabilities effective for comic episode catalog.
final class ComicEpisodeCatalogCapabilities {
  /// Creates a [ComicEpisodeCatalogCapabilities].
  const ComicEpisodeCatalogCapabilities(this.values);

  /// Per-capability support values.
  final DataCapabilitySet<ComicEpisodeCatalogCapability> values;

  /// Whether the requested capability is supported.
  bool supports(ComicEpisodeCatalogCapability capability) =>
      values.supports(capability);
}

/// Loads comic episode catalog data through a source-neutral contract.
abstract interface class ComicEpisodeCatalogRepository {
  /// Capabilities declared by this source.
  ComicEpisodeCatalogSourceCapabilities get capabilities;

  /// Loads catalog and returns a structured result.
  Future<
    DataReadResult<ComicEpisodeImageCatalog, ComicEpisodeCatalogCapabilities>
  >
  loadCatalog(ComicEpisodeCatalogRequest request);
}

/// Validated request for comic thread discovery.
final class ComicThreadDiscoveryRequest {
  /// Creates a [ComicThreadDiscoveryRequest].
  const ComicThreadDiscoveryRequest({required this.sourceTid});

  /// Stable source thread identifier.
  final String sourceTid;
}

/// Source-neutral comic thread discovery image reference.
final class ComicThreadDiscoveryImageReference {
  /// Creates a [ComicThreadDiscoveryImageReference].
  const ComicThreadDiscoveryImageReference({
    required this.url,
    required this.origin,
    this.attachmentId,
  });

  /// Source-provided URL after validation.
  final String url;

  /// Origin reported for this value.
  final ComicEpisodeImageOrigin origin;

  /// Stable attachment identifier when available.
  final String? attachmentId;
}

/// Source-neutral comic thread discovery post.
final class ComicThreadDiscoveryPost {
  /// Creates a [ComicThreadDiscoveryPost].
  const ComicThreadDiscoveryPost({
    required this.pid,
    required this.authorId,
    required this.floorNumber,
    required this.isFirst,
    required this.messageHtml,
    required this.imageReferences,
  });

  /// Stable post identifier.
  final String pid;

  /// Stable author identifier.
  final String authorId;

  /// Floor number.
  final int floorNumber;

  /// Is first.
  final bool isFirst;

  /// Message html.
  final String messageHtml;

  /// Image references.
  final List<ComicThreadDiscoveryImageReference> imageReferences;
}

/// Source-neutral comic thread discovery document.
final class ComicThreadDiscoveryDocument {
  /// Creates a [ComicThreadDiscoveryDocument].
  const ComicThreadDiscoveryDocument({
    required this.tid,
    required this.fid,
    required this.typeId,
    required this.subject,
    required this.posts,
  });

  /// Stable thread identifier.
  final String tid;

  /// Stable forum identifier.
  final String fid;

  /// Type id.
  final String typeId;

  /// Subject.
  final String subject;

  /// Posts.
  final List<ComicThreadDiscoveryPost> posts;
}

/// Capabilities exposed by comic thread discovery.
enum ComicThreadDiscoveryCapability {
  /// Stable thread identity.
  stableThreadIdentity,

  /// Forum classification.
  forumClassification,

  /// Ordered posts.
  orderedPosts,

  /// Stable post identity.
  stablePostIdentity,

  /// Reliable first post identity.
  reliableFirstPostIdentity,

  /// Renderable body.
  renderableBody,

  /// Normalized image references.
  normalizedImageReferences,

  /// Attachment identity.
  attachmentIdentity,
}

/// Capabilities declared by the comic thread discovery source.
final class ComicThreadDiscoverySourceCapabilities {
  /// Creates a [ComicThreadDiscoverySourceCapabilities].
  const ComicThreadDiscoverySourceCapabilities(this.values);

  /// Per-capability support values.
  final DataCapabilitySet<ComicThreadDiscoveryCapability> values;

  /// Whether the requested capability is supported.
  bool supports(ComicThreadDiscoveryCapability capability) =>
      values.supports(capability);
}

/// Capabilities effective for comic thread discovery.
final class ComicThreadDiscoveryCapabilities {
  /// Creates a [ComicThreadDiscoveryCapabilities].
  const ComicThreadDiscoveryCapabilities(this.values);

  /// Per-capability support values.
  final DataCapabilitySet<ComicThreadDiscoveryCapability> values;

  /// Whether the requested capability is supported.
  bool supports(ComicThreadDiscoveryCapability capability) =>
      values.supports(capability);
}

/// Loads comic thread discovery data through a source-neutral contract.
abstract interface class ComicThreadDiscoveryRepository {
  /// Capabilities declared by this source.
  ComicThreadDiscoverySourceCapabilities get capabilities;

  /// Comic thread discovery document.
  Future<
    DataReadResult<
      ComicThreadDiscoveryDocument,
      ComicThreadDiscoveryCapabilities
    >
  >
  load(ComicThreadDiscoveryRequest request);
}
