import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/comic/domain/models/comic_episode_image_catalog.dart';

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

  bool supports(ComicEpisodeCatalogCapability capability) {
    return values.supports(capability);
  }

  ComicEpisodeCatalogCapabilities toReadCapabilities() {
    return ComicEpisodeCatalogCapabilities(values);
  }
}

final class ComicEpisodeCatalogCapabilities {
  const ComicEpisodeCatalogCapabilities(this.values);

  final DataCapabilitySet<ComicEpisodeCatalogCapability> values;

  bool supports(ComicEpisodeCatalogCapability capability) {
    return values.supports(capability);
  }
}

abstract interface class ComicEpisodeCatalogRepository {
  ComicEpisodeCatalogSourceCapabilities get capabilities;

  Future<
    DataReadResult<ComicEpisodeImageCatalog, ComicEpisodeCatalogCapabilities>
  >
  loadCatalog(ComicEpisodeCatalogRequest request);
}
