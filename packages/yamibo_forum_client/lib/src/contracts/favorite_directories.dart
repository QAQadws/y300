/// Read contracts for remote forum and thread favorite directories.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';
import '../network/forum_request.dart';

final class FavoriteForumDirectoryQuery {
  const FavoriteForumDirectoryQuery({this.cancellation});

  final ForumRequestCancellation? cancellation;
}

final class FavoriteForumDirectoryData {
  const FavoriteForumDirectoryData({required this.items});
  final List<FavoriteForumEntry> items;
}

final class FavoriteForumEntry {
  const FavoriteForumEntry({
    required this.fid,
    required this.title,
    this.remoteFavoriteId,
    this.description,
    this.threadCount,
    this.postCount,
    this.todayPostCount,
  });
  final String fid;
  final String title;
  final String? remoteFavoriteId;
  final String? description;
  final int? threadCount;
  final int? postCount;
  final int? todayPostCount;
}

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
  bool supports(FavoriteForumDirectoryCapability capability) =>
      values.supports(capability);
  FavoriteForumDirectoryReadCapabilities toReadCapabilities() =>
      FavoriteForumDirectoryReadCapabilities(values: values);
}

final class FavoriteForumDirectoryReadCapabilities {
  const FavoriteForumDirectoryReadCapabilities({required this.values});
  final DataCapabilitySet<FavoriteForumDirectoryCapability> values;
  bool supports(FavoriteForumDirectoryCapability capability) =>
      values.supports(capability);
  FavoriteForumDirectoryReadCapabilities intersect(
    FavoriteForumDirectoryReadCapabilities other,
  ) => FavoriteForumDirectoryReadCapabilities(
    values: values.intersect(other.values),
  );
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

final class FavoriteThreadDirectoryQuery {
  const FavoriteThreadDirectoryQuery({this.page = 1, this.cancellation});
  final int page;
  final ForumRequestCancellation? cancellation;
}

final class FavoriteThreadDirectoryData {
  const FavoriteThreadDirectoryData({
    required this.items,
    required this.pagination,
  });
  final List<FavoriteThreadReference> items;
  final FavoriteThreadPagination pagination;
}

final class FavoriteThreadReference {
  const FavoriteThreadReference({
    required this.tid,
    required this.title,
    this.remoteFavoriteId,
    this.description,
    this.authorName,
    this.replyCount,
    this.favoritedAt,
  });
  final String tid;
  final String title;
  final String? remoteFavoriteId;
  final String? description;
  final String? authorName;
  final int? replyCount;
  final DateTime? favoritedAt;
}

final class FavoriteThreadPagination {
  const FavoriteThreadPagination({
    required this.currentPage,
    this.pageSize,
    this.totalItems,
    this.totalPages,
    this.hasPrevious,
    this.hasNext,
  });
  final int currentPage;
  final int? pageSize;
  final int? totalItems;
  final int? totalPages;
  final bool? hasPrevious;
  final bool? hasNext;
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
  bool supports(FavoriteThreadDirectoryCapability capability) =>
      values.supports(capability);
  FavoriteThreadDirectoryReadCapabilities toReadCapabilities() =>
      FavoriteThreadDirectoryReadCapabilities(
        values: values,
        paginationPrecision: paginationPrecision,
      );
}

final class FavoriteThreadDirectoryReadCapabilities {
  const FavoriteThreadDirectoryReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });
  final DataCapabilitySet<FavoriteThreadDirectoryCapability> values;
  final PaginationPrecision paginationPrecision;
  bool supports(FavoriteThreadDirectoryCapability capability) =>
      values.supports(capability);
  FavoriteThreadDirectoryReadCapabilities intersect(
    FavoriteThreadDirectoryReadCapabilities other,
  ) => FavoriteThreadDirectoryReadCapabilities(
    values: values.intersect(other.values),
    paginationPrecision: paginationPrecision.intersect(
      other.paginationPrecision,
    ),
  );
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
