import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';

enum UserBlogDetailCapability {
  stableBlogIdentity,
  stableOwnerIdentity,
  title,
  bodyMarkup,
  author,
  avatarReference,
  publishedAtText,
  viewCount,
  commentCount,
  orderedComments,
  stableCommentIdentity,
  commentAuthor,
  commentAvatarReference,
  commentPublishedAtText,
  commentBodyMarkup,
  commentingAvailability,
}

final class UserBlogDetailSourceCapabilities {
  const UserBlogDetailSourceCapabilities({required this.values});

  final DataCapabilitySet<UserBlogDetailCapability> values;

  bool supports(UserBlogDetailCapability capability) {
    return values.supports(capability);
  }

  UserBlogDetailReadCapabilities toReadCapabilities() {
    return UserBlogDetailReadCapabilities(values: values);
  }
}

final class UserBlogDetailReadCapabilities {
  const UserBlogDetailReadCapabilities({required this.values});

  final DataCapabilitySet<UserBlogDetailCapability> values;

  bool supports(UserBlogDetailCapability capability) {
    return values.supports(capability);
  }

  UserBlogDetailReadCapabilities intersect(
    UserBlogDetailReadCapabilities other,
  ) {
    return UserBlogDetailReadCapabilities(
      values: values.intersect(other.values),
    );
  }
}

abstract interface class UserBlogDetailRepository {
  UserBlogDetailSourceCapabilities get capabilities;

  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
