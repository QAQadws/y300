import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/comic/domain/models/comic_thread_discovery_models.dart';

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

  bool supports(ComicThreadDiscoveryCapability capability) {
    return values.supports(capability);
  }
}

final class ComicThreadDiscoveryCapabilities {
  const ComicThreadDiscoveryCapabilities(this.values);

  final DataCapabilitySet<ComicThreadDiscoveryCapability> values;

  bool supports(ComicThreadDiscoveryCapability capability) {
    return values.supports(capability);
  }
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
