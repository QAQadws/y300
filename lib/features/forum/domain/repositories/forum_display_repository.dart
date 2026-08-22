import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/forum/domain/models/forum_display_models.dart';

enum ForumDisplayCapability {
  forumIdentity,
  orderedThreadSummaries,
  richThreadSummaries,
  threadTypeQuery,
  lastPostOrdering,
  opaqueQueryParameters,
  forumChrome,
  filters,
  subForums,
  topEntries,
  postingEntry,
  searchEntry,
  favoriteState,
  directionalPagination,
  exactPagination,
}

final class ForumDisplaySourceCapabilities {
  const ForumDisplaySourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<ForumDisplayCapability> values;
  final PaginationPrecision paginationPrecision;

  static final full = ForumDisplaySourceCapabilities(
    values: DataCapabilitySet<ForumDisplayCapability>.supported(
      ForumDisplayCapability.values,
    ),
    paginationPrecision: PaginationPrecision.exact,
  );

  bool supports(ForumDisplayCapability capability) {
    return values.supports(capability);
  }

  ForumDisplayReadCapabilities toReadCapabilities() {
    return ForumDisplayReadCapabilities(
      values: values,
      paginationPrecision: paginationPrecision,
    );
  }
}

final class ForumDisplayReadCapabilities {
  const ForumDisplayReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<ForumDisplayCapability> values;
  final PaginationPrecision paginationPrecision;

  bool supports(ForumDisplayCapability capability) {
    return values.supports(capability);
  }

  ForumDisplayReadCapabilities intersect(
    ForumDisplayReadCapabilities other,
  ) {
    return ForumDisplayReadCapabilities(
      values: values.intersect(other.values),
      paginationPrecision: _weakerPagination(
        paginationPrecision,
        other.paginationPrecision,
      ),
    );
  }

  static PaginationPrecision _weakerPagination(
    PaginationPrecision left,
    PaginationPrecision right,
  ) {
    if (left == right) {
      return left;
    }
    const rank = <PaginationPrecision, int>{
      PaginationPrecision.exact: 0,
      PaginationPrecision.directional: 1,
      PaginationPrecision.totalBased: 2,
      PaginationPrecision.heuristic: 3,
      PaginationPrecision.unknown: 4,
    };
    return rank[left]! >= rank[right]! ? left : right;
  }
}

abstract interface class ForumDisplayRepository {
  ForumDisplaySourceCapabilities get capabilities;

  Future<
    DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>
  > getForumDisplayByQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

extension ForumDisplayRepositoryConvenience on ForumDisplayRepository {
  Future<DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>>
  getForumDisplay({
    required String fid,
    int page = 1,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    return getForumDisplayByQuery(
      ForumDisplayQuery.initial(fid: fid).copyWithPage(page),
      cachePolicy: cachePolicy,
    );
  }
}
