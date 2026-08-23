import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';

enum FavoriteForumDirectoryCapability {
  stableForumIdentity,
  stableRemoteFavoriteIdentity,
  orderedForums,
  forumTitle,
  forumDescription,
  forumThreadCount,
  forumPostCount,
  forumTodayPostCount,
}

final class FavoriteForumDirectorySourceCapabilities {
  const FavoriteForumDirectorySourceCapabilities({required this.values});

  final DataCapabilitySet<FavoriteForumDirectoryCapability> values;

  bool supports(FavoriteForumDirectoryCapability capability) {
    return values.supports(capability);
  }

  FavoriteForumDirectoryReadCapabilities toReadCapabilities() {
    return FavoriteForumDirectoryReadCapabilities(values: values);
  }
}

final class FavoriteForumDirectoryReadCapabilities {
  const FavoriteForumDirectoryReadCapabilities({required this.values});

  final DataCapabilitySet<FavoriteForumDirectoryCapability> values;

  bool supports(FavoriteForumDirectoryCapability capability) {
    return values.supports(capability);
  }

  FavoriteForumDirectoryReadCapabilities intersect(
    FavoriteForumDirectoryReadCapabilities other,
  ) {
    return FavoriteForumDirectoryReadCapabilities(
      values: values.intersect(other.values),
    );
  }
}

abstract interface class FavoriteForumDirectoryRepository {
  FavoriteForumDirectorySourceCapabilities get capabilities;

  Future<
    DataReadResult<
      FavoriteForumDirectoryData,
      FavoriteForumDirectoryReadCapabilities
    >
  >
  load(
    FavoriteForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

enum FavoriteThreadDirectoryCapability {
  stableThreadIdentity,
  stableRemoteFavoriteIdentity,
  orderedThreads,
  threadTitle,
  threadDescription,
  threadAuthor,
  threadReplyCount,
  favoritedAt,
  directionalPagination,
  pageSize,
  totalItemCount,
  totalPageCount,
}

final class FavoriteThreadDirectorySourceCapabilities {
  const FavoriteThreadDirectorySourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<FavoriteThreadDirectoryCapability> values;
  final PaginationPrecision paginationPrecision;

  bool supports(FavoriteThreadDirectoryCapability capability) {
    return values.supports(capability);
  }

  FavoriteThreadDirectoryReadCapabilities toReadCapabilities() {
    return FavoriteThreadDirectoryReadCapabilities(
      values: values,
      paginationPrecision: paginationPrecision,
    );
  }
}

final class FavoriteThreadDirectoryReadCapabilities {
  const FavoriteThreadDirectoryReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<FavoriteThreadDirectoryCapability> values;
  final PaginationPrecision paginationPrecision;

  bool supports(FavoriteThreadDirectoryCapability capability) {
    return values.supports(capability);
  }

  FavoriteThreadDirectoryReadCapabilities intersect(
    FavoriteThreadDirectoryReadCapabilities other,
  ) {
    return FavoriteThreadDirectoryReadCapabilities(
      values: values.intersect(other.values),
      paginationPrecision: paginationPrecision.intersect(
        other.paginationPrecision,
      ),
    );
  }
}

abstract interface class FavoriteThreadDirectoryRepository {
  FavoriteThreadDirectorySourceCapabilities get capabilities;

  Future<
    DataReadResult<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >
  >
  load(
    FavoriteThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
