import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/search/domain/models/forum_search_models.dart';

enum ForumSearchCapability {
  stableTopicIdentity,
  orderedTopics,
  topicTitle,
  topicForum,
  topicAuthor,
  topicPublishedAt,
  directionalPagination,
  searchContinuation,
}

final class ForumSearchSourceCapabilities {
  const ForumSearchSourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<ForumSearchCapability> values;
  final PaginationPrecision paginationPrecision;

  bool supports(ForumSearchCapability capability) {
    return values.supports(capability);
  }

  ForumSearchReadCapabilities toReadCapabilities() {
    return ForumSearchReadCapabilities(
      values: values,
      paginationPrecision: paginationPrecision,
    );
  }
}

final class ForumSearchReadCapabilities {
  const ForumSearchReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<ForumSearchCapability> values;
  final PaginationPrecision paginationPrecision;

  bool supports(ForumSearchCapability capability) {
    return values.supports(capability);
  }

  ForumSearchReadCapabilities intersect(ForumSearchReadCapabilities other) {
    return ForumSearchReadCapabilities(
      values: values.intersect(other.values),
      paginationPrecision: paginationPrecision.intersect(
        other.paginationPrecision,
      ),
    );
  }
}

abstract interface class ForumSearchRepository {
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>> load(
    ForumSearchQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });

  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
