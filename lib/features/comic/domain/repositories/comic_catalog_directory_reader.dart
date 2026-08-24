import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';

abstract interface class ComicCatalogRequestGate {
  Future<T> run<T>(Future<T> Function() action);
}

final class ComicCatalogDirectoryRequest {
  const ComicCatalogDirectoryRequest({
    required this.catalogUrl,
    this.maxPages = 10,
    this.requestGate,
  });

  final String catalogUrl;
  final int maxPages;
  final ComicCatalogRequestGate? requestGate;
}

final class ComicCatalogDirectory {
  const ComicCatalogDirectory({required this.links});

  final List<ComicEpisodeLink> links;
}

enum ComicCatalogDirectoryCapability {
  stableCatalogIdentity,
  orderedEntries,
  stableThreadIdentity,
  entryTitle,
}

final class ComicCatalogDirectoryCapabilities {
  const ComicCatalogDirectoryCapabilities({required this.values});

  final DataCapabilitySet<ComicCatalogDirectoryCapability> values;

  bool supports(ComicCatalogDirectoryCapability capability) =>
      values.supports(capability);
}

abstract interface class ComicCatalogDirectoryReader {
  Future<
    DataReadResult<ComicCatalogDirectory, ComicCatalogDirectoryCapabilities>
  >
  load(ComicCatalogDirectoryRequest request);
}
