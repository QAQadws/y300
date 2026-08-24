import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/repositories/comic_catalog_directory_reader.dart';

final class ForumTagComicCatalogDirectoryReader
    implements ComicCatalogDirectoryReader {
  const ForumTagComicCatalogDirectoryReader({
    required ForumTagDirectoryRepository repository,
    required ForumReferenceResolver references,
  }) : _repository = repository,
       _references = references;

  final ForumTagDirectoryRepository _repository;
  final ForumReferenceResolver _references;

  @override
  Future<
    DataReadResult<ComicCatalogDirectory, ComicCatalogDirectoryCapabilities>
  >
  load(ComicCatalogDirectoryRequest request) async {
    final tagId = _references.extractTagId(request.catalogUrl);
    final maxPages = request.maxPages.clamp(1, 100);
    if (tagId == null) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'invalid_catalog_reference',
        diagnosticMessage: 'invalid_catalog_reference',
      );
    }

    final firstPage = _references.extractTagPage(request.catalogUrl);
    final links = <String, ComicEpisodeLink>{};
    DataReadMetadata? metadata;
    var capabilities = ComicCatalogDirectoryCapabilities(
      values: DataCapabilitySet<ComicCatalogDirectoryCapability>.supported(
        ComicCatalogDirectoryCapability.values,
      ),
    );
    var page = firstPage;
    var pagesRead = 0;

    while (pagesRead < maxPages) {
      final result = await _run(
        request.requestGate,
        () => _repository.load(
          ForumTagDirectoryQuery(tagId: tagId, page: page),
          cachePolicy: CacheLoadPolicy.networkFirst,
        ),
      );
      if (result
          case final DataReadFailure<
                ForumTagDirectoryData,
                ForumTagDirectoryReadCapabilities
              >
              failure) {
        if (pagesRead == 0) return failure.retype();
        break;
      }
      final success =
          result
              as DataReadSuccess<
                ForumTagDirectoryData,
                ForumTagDirectoryReadCapabilities
              >;
      if (success.data.tag.id != tagId ||
          !success.capabilities.supports(
            ForumTagDirectoryCapability.stableTagIdentity,
          ) ||
          !success.capabilities.supports(
            ForumTagDirectoryCapability.orderedTopics,
          ) ||
          !success.capabilities.supports(
            ForumTagDirectoryCapability.stableTopicIdentity,
          )) {
        return const DataReadFailure(
          kind: DataReadFailureKind.unsupported,
          code: 'catalog_capability_unavailable',
          diagnosticMessage: 'catalog_capability_unavailable',
        );
      }

      metadata = metadata == null
          ? success.metadata
          : metadata.merge(success.metadata);
      capabilities = ComicCatalogDirectoryCapabilities(
        values: capabilities.values.intersect(
          DataCapabilitySet<ComicCatalogDirectoryCapability>.from(
            supported: <ComicCatalogDirectoryCapability>[
              ComicCatalogDirectoryCapability.stableCatalogIdentity,
              ComicCatalogDirectoryCapability.orderedEntries,
              ComicCatalogDirectoryCapability.stableThreadIdentity,
              if (success.capabilities.supports(
                ForumTagDirectoryCapability.topicTitle,
              ))
                ComicCatalogDirectoryCapability.entryTitle,
            ],
            unsupported: <ComicCatalogDirectoryCapability>[
              if (!success.capabilities.supports(
                ForumTagDirectoryCapability.topicTitle,
              ))
                ComicCatalogDirectoryCapability.entryTitle,
            ],
          ),
        ),
      );
      for (final topic in success.data.topics) {
        links.putIfAbsent(
          topic.tid,
          () => ComicEpisodeLink(
            url: topic.threadUrl ?? _threadUrl(topic.tid),
            rawText: topic.title.isEmpty ? '目录条目' : topic.title,
            episodeTitle: topic.title.isEmpty ? null : topic.title,
          ),
        );
      }

      pagesRead += 1;
      final pagination = success.data.pagination;
      final totalPages = pagination.totalPages;
      final hasNext =
          pagination.hasNext ??
          (totalPages != null && pagination.currentPage < totalPages);
      if (!hasNext) break;
      page = pagination.currentPage + 1;
    }

    return DataReadSuccess(
      data: ComicCatalogDirectory(
        links: List<ComicEpisodeLink>.unmodifiable(links.values),
      ),
      capabilities: capabilities,
      metadata: metadata ?? const DataReadMetadata.network(),
    );
  }

  Future<T> _run<T>(ComicCatalogRequestGate? gate, Future<T> Function() load) =>
      gate == null ? load() : gate.run(load);

  String _threadUrl(String tid) => Uri.parse(_references.siteOrigin)
      .resolve('/forum.php')
      .replace(
        queryParameters: <String, String>{'mod': 'viewthread', 'tid': tid},
      )
      .toString();
}
