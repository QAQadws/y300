import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Empty, immediate lists for navigation tests, without images or network.
final class BlogDirectoryFixture implements UserBlogDirectoryRepository {
  final queries = <UserBlogDirectoryQuery>[];

  @override
  final capabilities = UserBlogDirectorySourceCapabilities(
    values: DataCapabilitySet.from(
      supported: UserBlogDirectoryCapability.values,
    ),
    paginationPrecision: PaginationPrecision.exact,
  );

  @override
  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  load(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    queries.add(query);
    return DataReadSuccess(
      data: UserBlogDirectoryData(
        scope: query.scope,
        order: query.order,
        items: const [],
        pagination: UserBlogPagination(currentPage: query.page),
      ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}
