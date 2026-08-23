import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';

enum UserBlogDirectoryCapability {
  stableFeedIdentity,
  orderedEntries,
  stableBlogIdentity,
  stableOwnerIdentity,
  title,
  excerpt,
  author,
  avatarReference,
  publishedAtText,
  directionalPagination,
  totalPageCount,
}

final class UserBlogDirectorySourceCapabilities {
  const UserBlogDirectorySourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<UserBlogDirectoryCapability> values;
  final PaginationPrecision paginationPrecision;

  bool supports(UserBlogDirectoryCapability capability) {
    return values.supports(capability);
  }

  UserBlogDirectoryReadCapabilities toReadCapabilities() {
    return UserBlogDirectoryReadCapabilities(
      values: values,
      paginationPrecision: paginationPrecision,
    );
  }
}

final class UserBlogDirectoryReadCapabilities {
  const UserBlogDirectoryReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<UserBlogDirectoryCapability> values;
  final PaginationPrecision paginationPrecision;

  bool supports(UserBlogDirectoryCapability capability) {
    return values.supports(capability);
  }

  UserBlogDirectoryReadCapabilities intersect(
    UserBlogDirectoryReadCapabilities other,
  ) {
    return UserBlogDirectoryReadCapabilities(
      values: values.intersect(other.values),
      paginationPrecision: paginationPrecision.intersect(
        other.paginationPrecision,
      ),
    );
  }
}

abstract interface class UserBlogDirectoryRepository {
  UserBlogDirectorySourceCapabilities get capabilities;

  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  load(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
