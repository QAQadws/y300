/// Read contracts for current/public profiles and user blog content.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';

final class ProfileUserIdentity {
  const ProfileUserIdentity({required this.userId, this.displayName});
  final String userId;
  final String? displayName;
}

final class CurrentUserProfileQuery {
  const CurrentUserProfileQuery();
}

final class CurrentUserProfileData {
  const CurrentUserProfileData({
    required this.identity,
    this.avatarUrl,
    this.groupId,
    this.creditTotal,
    this.postCount,
    this.threadCount,
  });
  final ProfileUserIdentity identity;
  final String? avatarUrl;
  final String? groupId;
  final int? creditTotal;
  final int? postCount;
  final int? threadCount;
}

enum CurrentUserProfileCapability {
  stableUserIdentity,
  userName,
  avatarReference,
  groupIdentity,
  creditTotal,
  postCount,
  threadCount,
}

final class CurrentUserProfileSourceCapabilities {
  const CurrentUserProfileSourceCapabilities({required this.values});
  final DataCapabilitySet<CurrentUserProfileCapability> values;
  bool supports(CurrentUserProfileCapability c) => values.supports(c);
  CurrentUserProfileReadCapabilities toReadCapabilities() =>
      CurrentUserProfileReadCapabilities(values: values);
}

final class CurrentUserProfileReadCapabilities {
  const CurrentUserProfileReadCapabilities({required this.values});
  final DataCapabilitySet<CurrentUserProfileCapability> values;
  bool supports(CurrentUserProfileCapability c) => values.supports(c);
  CurrentUserProfileReadCapabilities intersect(
    CurrentUserProfileReadCapabilities o,
  ) => CurrentUserProfileReadCapabilities(values: values.intersect(o.values));
}

abstract interface class CurrentUserProfileRepository {
  CurrentUserProfileSourceCapabilities get capabilities;
  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  load(
    CurrentUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

enum ForumUserProfileView { public, self }

final class ForumUserProfileQuery {
  const ForumUserProfileQuery({
    required this.userId,
    this.view = ForumUserProfileView.public,
  });
  final String userId;
  final ForumUserProfileView view;
  @override
  bool operator ==(Object other) =>
      other is ForumUserProfileQuery &&
      other.userId == userId &&
      other.view == view;
  @override
  int get hashCode => Object.hash(userId, view);
}

final class ForumUserProfileData {
  const ForumUserProfileData({
    required this.identity,
    required this.metrics,
    required this.details,
    this.avatarUrl,
    this.coverUrl,
    this.signatureHtml,
  });
  final ProfileUserIdentity identity;
  final String? avatarUrl;
  final String? coverUrl;
  final String? signatureHtml;
  final List<ForumUserProfileMetric> metrics;
  final List<ForumUserProfileDetail> details;
}

final class ForumUserProfileMetric {
  const ForumUserProfileMetric({required this.label, required this.value});
  final String label;
  final String value;
}

final class ForumUserProfileDetail {
  const ForumUserProfileDetail({required this.label, required this.value});
  final String label;
  final String value;
}

enum ForumUserProfileCapability {
  stableUserIdentity,
  userName,
  avatarReference,
  coverReference,
  signatureMarkup,
  orderedMetrics,
  orderedDetails,
}

final class ForumUserProfileSourceCapabilities {
  const ForumUserProfileSourceCapabilities({required this.values});
  final DataCapabilitySet<ForumUserProfileCapability> values;
  bool supports(ForumUserProfileCapability c) => values.supports(c);
  ForumUserProfileReadCapabilities toReadCapabilities() =>
      ForumUserProfileReadCapabilities(values: values);
}

final class ForumUserProfileReadCapabilities {
  const ForumUserProfileReadCapabilities({required this.values});
  final DataCapabilitySet<ForumUserProfileCapability> values;
  bool supports(ForumUserProfileCapability c) => values.supports(c);
  ForumUserProfileReadCapabilities intersect(
    ForumUserProfileReadCapabilities o,
  ) => ForumUserProfileReadCapabilities(values: values.intersect(o.values));
}

abstract interface class ForumUserProfileRepository {
  ForumUserProfileSourceCapabilities get capabilities;
  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

enum UserBlogFeedScope { friends, self, public }

enum UserBlogOrder { latest, recommended }

final class UserBlogDirectoryQuery {
  const UserBlogDirectoryQuery({
    required this.scope,
    this.order,
    this.page = 1,
  });
  const UserBlogDirectoryQuery.public({
    this.order = UserBlogOrder.latest,
    this.page = 1,
  }) : scope = UserBlogFeedScope.public;
  const UserBlogDirectoryQuery.friends({this.page = 1})
    : scope = UserBlogFeedScope.friends,
      order = null;
  const UserBlogDirectoryQuery.self({this.page = 1})
    : scope = UserBlogFeedScope.self,
      order = null;
  final UserBlogFeedScope scope;
  final UserBlogOrder? order;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is UserBlogDirectoryQuery &&
      other.scope == scope &&
      other.order == order &&
      other.page == page;

  @override
  int get hashCode => Object.hash(scope, order, page);
}

final class UserBlogDirectoryData {
  const UserBlogDirectoryData({
    required this.scope,
    required this.order,
    required this.items,
    required this.pagination,
  });
  final UserBlogFeedScope scope;
  final UserBlogOrder? order;
  final List<UserBlogSummary> items;
  final UserBlogPagination pagination;
}

final class UserBlogSummary {
  const UserBlogSummary({
    required this.blogId,
    required this.ownerUserId,
    required this.title,
    this.authorName,
    this.excerpt,
    this.avatarUrl,
    this.publishedAtText,
  });
  final String blogId;
  final String ownerUserId;
  final String title;
  final String? authorName;
  final String? excerpt;
  final String? avatarUrl;
  final String? publishedAtText;
}

final class UserBlogPagination {
  const UserBlogPagination({
    required this.currentPage,
    this.totalPages,
    this.hasPrevious,
    this.hasNext,
  });
  final int currentPage;
  final int? totalPages;
  final bool? hasPrevious;
  final bool? hasNext;
}

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
  bool supports(UserBlogDirectoryCapability c) => values.supports(c);
  UserBlogDirectoryReadCapabilities toReadCapabilities() =>
      UserBlogDirectoryReadCapabilities(
        values: values,
        paginationPrecision: paginationPrecision,
      );
}

final class UserBlogDirectoryReadCapabilities {
  const UserBlogDirectoryReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });
  final DataCapabilitySet<UserBlogDirectoryCapability> values;
  final PaginationPrecision paginationPrecision;
  bool supports(UserBlogDirectoryCapability c) => values.supports(c);
  UserBlogDirectoryReadCapabilities intersect(
    UserBlogDirectoryReadCapabilities o,
  ) => UserBlogDirectoryReadCapabilities(
    values: values.intersect(o.values),
    paginationPrecision: paginationPrecision.intersect(o.paginationPrecision),
  );
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

final class UserBlogDetailQuery {
  const UserBlogDetailQuery({required this.ownerUserId, required this.blogId});
  final String ownerUserId;
  final String blogId;

  @override
  bool operator ==(Object other) =>
      other is UserBlogDetailQuery &&
      other.ownerUserId == ownerUserId &&
      other.blogId == blogId;

  @override
  int get hashCode => Object.hash(ownerUserId, blogId);
}

final class UserBlogDetailData {
  const UserBlogDetailData({
    required this.blogId,
    required this.ownerUserId,
    required this.title,
    required this.bodyHtml,
    required this.comments,
    this.authorName,
    this.avatarUrl,
    this.publishedAtText,
    this.viewCount,
    this.commentCount,
    this.commentsOpen,
  });
  final String blogId;
  final String ownerUserId;
  final String title;
  final String bodyHtml;
  final String? authorName;
  final String? avatarUrl;
  final String? publishedAtText;
  final int? viewCount;
  final int? commentCount;
  final List<UserBlogComment> comments;
  final bool? commentsOpen;
}

final class UserBlogComment {
  const UserBlogComment({
    required this.commentId,
    required this.authorName,
    required this.bodyHtml,
    this.authorUserId,
    this.avatarUrl,
    this.publishedAtText,
  });
  final String commentId;
  final String authorName;
  final String bodyHtml;
  final String? authorUserId;
  final String? avatarUrl;
  final String? publishedAtText;
}

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
  bool supports(UserBlogDetailCapability c) => values.supports(c);
  UserBlogDetailReadCapabilities toReadCapabilities() =>
      UserBlogDetailReadCapabilities(values: values);
}

final class UserBlogDetailReadCapabilities {
  const UserBlogDetailReadCapabilities({required this.values});
  final DataCapabilitySet<UserBlogDetailCapability> values;
  bool supports(UserBlogDetailCapability c) => values.supports(c);
  UserBlogDetailReadCapabilities intersect(UserBlogDetailReadCapabilities o) =>
      UserBlogDetailReadCapabilities(values: values.intersect(o.values));
}

abstract interface class UserBlogDetailRepository {
  UserBlogDetailSourceCapabilities get capabilities;
  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
