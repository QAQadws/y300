/// Source-neutral comic episode catalog and discovery contracts.
library;

import 'data_read_contract.dart';

enum ComicEpisodeImageOrigin { dom, attachment }

final class ComicEpisodeCatalogRequest {
  const ComicEpisodeCatalogRequest({required this.sourceTid});
  final String sourceTid;
}

final class ComicEpisodeImageReference {
  const ComicEpisodeImageReference({
    required this.url,
    required this.origin,
    this.attachmentId,
  });
  final String url;
  final ComicEpisodeImageOrigin origin;
  final String? attachmentId;
}

final class ComicEpisodeImageCatalog {
  const ComicEpisodeImageCatalog({
    required this.sourceTid,
    required this.images,
  });
  final String sourceTid;
  final List<ComicEpisodeImageReference> images;
}

enum ComicEpisodeCatalogCapability {
  stableSourceIdentity,
  reliableFirstPostIdentity,
  reliableImageOrder,
  imageOrigin,
  attachmentId,
}

final class ComicEpisodeCatalogSourceCapabilities {
  const ComicEpisodeCatalogSourceCapabilities(this.values);
  final DataCapabilitySet<ComicEpisodeCatalogCapability> values;
  bool supports(ComicEpisodeCatalogCapability capability) =>
      values.supports(capability);
  ComicEpisodeCatalogCapabilities toReadCapabilities() =>
      ComicEpisodeCatalogCapabilities(values);
}

final class ComicEpisodeCatalogCapabilities {
  const ComicEpisodeCatalogCapabilities(this.values);
  final DataCapabilitySet<ComicEpisodeCatalogCapability> values;
  bool supports(ComicEpisodeCatalogCapability capability) =>
      values.supports(capability);
}

abstract interface class ComicEpisodeCatalogRepository {
  ComicEpisodeCatalogSourceCapabilities get capabilities;
  Future<
    DataReadResult<ComicEpisodeImageCatalog, ComicEpisodeCatalogCapabilities>
  >
  loadCatalog(ComicEpisodeCatalogRequest request);
}

final class ComicThreadDiscoveryRequest {
  const ComicThreadDiscoveryRequest({required this.sourceTid});
  final String sourceTid;
}

final class ComicThreadDiscoveryImageReference {
  const ComicThreadDiscoveryImageReference({
    required this.url,
    required this.origin,
    this.attachmentId,
  });
  final String url;
  final ComicEpisodeImageOrigin origin;
  final String? attachmentId;
}

final class ComicThreadDiscoveryPost {
  const ComicThreadDiscoveryPost({
    required this.pid,
    required this.authorId,
    required this.floorNumber,
    required this.isFirst,
    required this.messageHtml,
    required this.imageReferences,
  });
  final String pid;
  final String authorId;
  final int floorNumber;
  final bool isFirst;
  final String messageHtml;
  final List<ComicThreadDiscoveryImageReference> imageReferences;
}

final class ComicThreadDiscoveryDocument {
  const ComicThreadDiscoveryDocument({
    required this.tid,
    required this.fid,
    required this.typeId,
    required this.subject,
    required this.posts,
  });
  final String tid;
  final String fid;
  final String typeId;
  final String subject;
  final List<ComicThreadDiscoveryPost> posts;
}

enum ComicThreadDiscoveryCapability {
  stableThreadIdentity,
  forumClassification,
  orderedPosts,
  stablePostIdentity,
  reliableFirstPostIdentity,
  renderableBody,
  normalizedImageReferences,
  attachmentIdentity,
}

final class ComicThreadDiscoverySourceCapabilities {
  const ComicThreadDiscoverySourceCapabilities(this.values);
  final DataCapabilitySet<ComicThreadDiscoveryCapability> values;
  bool supports(ComicThreadDiscoveryCapability capability) =>
      values.supports(capability);
}

final class ComicThreadDiscoveryCapabilities {
  const ComicThreadDiscoveryCapabilities(this.values);
  final DataCapabilitySet<ComicThreadDiscoveryCapability> values;
  bool supports(ComicThreadDiscoveryCapability capability) =>
      values.supports(capability);
}

abstract interface class ComicThreadDiscoveryRepository {
  ComicThreadDiscoverySourceCapabilities get capabilities;
  Future<
    DataReadResult<
      ComicThreadDiscoveryDocument,
      ComicThreadDiscoveryCapabilities
    >
  >
  load(ComicThreadDiscoveryRequest request);
}
