/// Read contracts for current/public profiles and user blog content.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';

/// Source-neutral profile user identity.
final class ProfileUserIdentity {
  /// Creates a [ProfileUserIdentity].
  const ProfileUserIdentity({required this.userId, this.displayName});

  /// Stable user identifier.
  final String userId;

  /// Display name.
  final String? displayName;
}

/// Query parameters for current user profile.
final class CurrentUserProfileQuery {
  /// Creates a [CurrentUserProfileQuery].
  const CurrentUserProfileQuery();
}

/// Source-neutral current user profile data.
final class CurrentUserProfileData {
  /// Creates a [CurrentUserProfileData].
  const CurrentUserProfileData({
    required this.identity,
    this.avatarUrl,
    this.groupId,
    this.creditTotal,
    this.postCount,
    this.threadCount,
  });

  /// Identity.
  final ProfileUserIdentity identity;

  /// Avatar url.
  final String? avatarUrl;

  /// Group id.
  final String? groupId;

  /// Credit total.
  final int? creditTotal;

  /// Post count.
  final int? postCount;

  /// Thread count.
  final int? threadCount;
}

/// Capabilities exposed by current user profile.
enum CurrentUserProfileCapability {
  /// Stable user identity.
  stableUserIdentity,

  /// User name.
  userName,

  /// Avatar reference.
  avatarReference,

  /// Group identity.
  groupIdentity,

  /// Credit total.
  creditTotal,

  /// Post count.
  postCount,

  /// Thread count.
  threadCount,
}

/// Capabilities declared by the current user profile source.
final class CurrentUserProfileSourceCapabilities {
  /// Creates a [CurrentUserProfileSourceCapabilities].
  const CurrentUserProfileSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<CurrentUserProfileCapability> values;

  /// Whether the requested capability is supported.
  bool supports(CurrentUserProfileCapability c) => values.supports(c);

  /// Converts this value to read capabilities.
  CurrentUserProfileReadCapabilities toReadCapabilities() =>
      CurrentUserProfileReadCapabilities(values: values);
}

/// Capabilities effective for one current user profile read.
final class CurrentUserProfileReadCapabilities {
  /// Creates a [CurrentUserProfileReadCapabilities].
  const CurrentUserProfileReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<CurrentUserProfileCapability> values;

  /// Whether the requested capability is supported.
  bool supports(CurrentUserProfileCapability c) => values.supports(c);

  /// Returns the conservative intersection with another value.
  CurrentUserProfileReadCapabilities intersect(
    CurrentUserProfileReadCapabilities o,
  ) => CurrentUserProfileReadCapabilities(values: values.intersect(o.values));
}

/// Loads current user profile data through a source-neutral contract.
abstract interface class CurrentUserProfileRepository {
  /// Capabilities declared by this source.
  CurrentUserProfileSourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  load(
    CurrentUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

/// Values describing forum user profile view.
enum ForumUserProfileView {
  /// Public.
  public,

  /// Self.
  self,
}

/// Query parameters for forum user profile.
final class ForumUserProfileQuery {
  /// Creates a [ForumUserProfileQuery].
  const ForumUserProfileQuery({
    required this.userId,
    this.view = ForumUserProfileView.public,
  });

  /// Stable user identifier.
  final String userId;

  /// View.
  final ForumUserProfileView view;
  @override
  bool operator ==(Object other) =>
      other is ForumUserProfileQuery &&
      other.userId == userId &&
      other.view == view;
  @override
  int get hashCode => Object.hash(userId, view);
}

/// Source-neutral forum user profile data.
final class ForumUserProfileData {
  /// Creates a [ForumUserProfileData].
  const ForumUserProfileData({
    required this.identity,
    required this.metrics,
    required this.details,
    this.avatarUrl,
    this.coverUrl,
    this.signatureHtml,
  });

  /// Identity.
  final ProfileUserIdentity identity;

  /// Avatar url.
  final String? avatarUrl;

  /// Cover url.
  final String? coverUrl;

  /// Signature html.
  final String? signatureHtml;

  /// Metrics.
  final List<ForumUserProfileMetric> metrics;

  /// Details.
  final List<ForumUserProfileDetail> details;
}

/// Source-neutral forum user profile metric.
final class ForumUserProfileMetric {
  /// Creates a [ForumUserProfileMetric].
  const ForumUserProfileMetric({required this.label, required this.value});

  /// Label.
  final String label;

  /// Value.
  final String value;
}

/// Source-neutral forum user profile detail.
final class ForumUserProfileDetail {
  /// Creates a [ForumUserProfileDetail].
  const ForumUserProfileDetail({required this.label, required this.value});

  /// Label.
  final String label;

  /// Value.
  final String value;
}

/// Capabilities exposed by forum user profile.
enum ForumUserProfileCapability {
  /// Stable user identity.
  stableUserIdentity,

  /// User name.
  userName,

  /// Avatar reference.
  avatarReference,

  /// Cover reference.
  coverReference,

  /// Signature markup.
  signatureMarkup,

  /// Ordered metrics.
  orderedMetrics,

  /// Ordered details.
  orderedDetails,
}

/// Capabilities declared by the forum user profile source.
final class ForumUserProfileSourceCapabilities {
  /// Creates a [ForumUserProfileSourceCapabilities].
  const ForumUserProfileSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumUserProfileCapability> values;

  /// Whether the requested capability is supported.
  bool supports(ForumUserProfileCapability c) => values.supports(c);

  /// Converts this value to read capabilities.
  ForumUserProfileReadCapabilities toReadCapabilities() =>
      ForumUserProfileReadCapabilities(values: values);
}

/// Capabilities effective for one forum user profile read.
final class ForumUserProfileReadCapabilities {
  /// Creates a [ForumUserProfileReadCapabilities].
  const ForumUserProfileReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumUserProfileCapability> values;

  /// Whether the requested capability is supported.
  bool supports(ForumUserProfileCapability c) => values.supports(c);

  /// Returns the conservative intersection with another value.
  ForumUserProfileReadCapabilities intersect(
    ForumUserProfileReadCapabilities o,
  ) => ForumUserProfileReadCapabilities(values: values.intersect(o.values));
}

/// Loads forum user profile data through a source-neutral contract.
abstract interface class ForumUserProfileRepository {
  /// Capabilities declared by this source.
  ForumUserProfileSourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

/// Values describing user blog feed scope.
enum UserBlogFeedScope {
  /// Friends.
  friends,

  /// Self.
  self,

  /// Public.
  public,
}

/// Values describing user blog order.
enum UserBlogOrder {
  /// Latest.
  latest,

  /// Recommended.
  recommended,
}

/// Query parameters for user blog directory.
final class UserBlogDirectoryQuery {
  /// Creates a [UserBlogDirectoryQuery].
  const UserBlogDirectoryQuery({
    required this.scope,
    this.order,
    this.page = 1,
  });

  /// Creates a [UserBlogDirectoryQuery].
  const UserBlogDirectoryQuery.public({
    this.order = UserBlogOrder.latest,
    this.page = 1,
  }) : scope = UserBlogFeedScope.public;

  /// Creates a [UserBlogDirectoryQuery].
  const UserBlogDirectoryQuery.friends({this.page = 1})
    : scope = UserBlogFeedScope.friends,
      order = null;

  /// Creates a [UserBlogDirectoryQuery].
  const UserBlogDirectoryQuery.self({this.page = 1})
    : scope = UserBlogFeedScope.self,
      order = null;

  /// Scope.
  final UserBlogFeedScope scope;

  /// Order.
  final UserBlogOrder? order;

  /// Requested or current one-based page.
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

/// Source-neutral user blog directory data.
final class UserBlogDirectoryData {
  /// Creates a [UserBlogDirectoryData].
  const UserBlogDirectoryData({
    required this.scope,
    required this.order,
    required this.items,
    required this.pagination,
  });

  /// Scope.
  final UserBlogFeedScope scope;

  /// Order.
  final UserBlogOrder? order;

  /// Items.
  final List<UserBlogSummary> items;

  /// Pagination.
  final UserBlogPagination pagination;
}

/// Source-neutral user blog summary.
final class UserBlogSummary {
  /// Creates a [UserBlogSummary].
  const UserBlogSummary({
    required this.blogId,
    required this.ownerUserId,
    required this.title,
    this.authorName,
    this.excerpt,
    this.avatarUrl,
    this.publishedAtText,
  });

  /// Blog id.
  final String blogId;

  /// Owner user id.
  final String ownerUserId;

  /// Title.
  final String title;

  /// Author name.
  final String? authorName;

  /// Excerpt.
  final String? excerpt;

  /// Avatar url.
  final String? avatarUrl;

  /// Published at text.
  final String? publishedAtText;
}

/// Source-neutral user blog pagination.
final class UserBlogPagination {
  /// Creates a [UserBlogPagination].
  const UserBlogPagination({
    required this.currentPage,
    this.totalPages,
    this.hasPrevious,
    this.hasNext,
  });

  /// Current one-based server page.
  final int currentPage;

  /// Exact total page count when the source proves it.
  final int? totalPages;

  /// Whether a preceding page is available when known.
  final bool? hasPrevious;

  /// Whether a following page is available when known.
  final bool? hasNext;
}

/// Capabilities exposed by user blog directory.
enum UserBlogDirectoryCapability {
  /// Stable feed identity.
  stableFeedIdentity,

  /// Ordered entries.
  orderedEntries,

  /// Stable blog identity.
  stableBlogIdentity,

  /// Stable owner identity.
  stableOwnerIdentity,

  /// Title.
  title,

  /// Excerpt.
  excerpt,

  /// Author.
  author,

  /// Avatar reference.
  avatarReference,

  /// Published at text.
  publishedAtText,

  /// Directional pagination.
  directionalPagination,

  /// Total page count.
  totalPageCount,
}

/// Capabilities declared by the user blog directory source.
final class UserBlogDirectorySourceCapabilities {
  /// Creates a [UserBlogDirectorySourceCapabilities].
  const UserBlogDirectorySourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<UserBlogDirectoryCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Whether the requested capability is supported.
  bool supports(UserBlogDirectoryCapability c) => values.supports(c);

  /// Converts this value to read capabilities.
  UserBlogDirectoryReadCapabilities toReadCapabilities() =>
      UserBlogDirectoryReadCapabilities(
        values: values,
        paginationPrecision: paginationPrecision,
      );
}

/// Capabilities effective for one user blog directory read.
final class UserBlogDirectoryReadCapabilities {
  /// Creates a [UserBlogDirectoryReadCapabilities].
  const UserBlogDirectoryReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<UserBlogDirectoryCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Whether the requested capability is supported.
  bool supports(UserBlogDirectoryCapability c) => values.supports(c);

  /// Returns the conservative intersection with another value.
  UserBlogDirectoryReadCapabilities intersect(
    UserBlogDirectoryReadCapabilities o,
  ) => UserBlogDirectoryReadCapabilities(
    values: values.intersect(o.values),
    paginationPrecision: paginationPrecision.intersect(o.paginationPrecision),
  );
}

/// Loads user blog directory data through a source-neutral contract.
abstract interface class UserBlogDirectoryRepository {
  /// Capabilities declared by this source.
  UserBlogDirectorySourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  load(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

/// Query parameters for user blog detail.
final class UserBlogDetailQuery {
  /// Creates a [UserBlogDetailQuery].
  const UserBlogDetailQuery({required this.ownerUserId, required this.blogId});

  /// Owner user id.
  final String ownerUserId;

  /// Blog id.
  final String blogId;

  @override
  bool operator ==(Object other) =>
      other is UserBlogDetailQuery &&
      other.ownerUserId == ownerUserId &&
      other.blogId == blogId;

  @override
  int get hashCode => Object.hash(ownerUserId, blogId);
}

/// Source-neutral user blog detail data.
final class UserBlogDetailData {
  /// Creates a [UserBlogDetailData].
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

  /// Blog id.
  final String blogId;

  /// Owner user id.
  final String ownerUserId;

  /// Title.
  final String title;

  /// Body html.
  final String bodyHtml;

  /// Author name.
  final String? authorName;

  /// Avatar url.
  final String? avatarUrl;

  /// Published at text.
  final String? publishedAtText;

  /// View count.
  final int? viewCount;

  /// Comment count.
  final int? commentCount;

  /// Comments.
  final List<UserBlogComment> comments;

  /// Comments open.
  final bool? commentsOpen;
}

/// Source-neutral user blog comment.
final class UserBlogComment {
  /// Creates a [UserBlogComment].
  const UserBlogComment({
    required this.commentId,
    required this.authorName,
    required this.bodyHtml,
    this.authorUserId,
    this.avatarUrl,
    this.publishedAtText,
  });

  /// Comment id.
  final String commentId;

  /// Author name.
  final String authorName;

  /// Body html.
  final String bodyHtml;

  /// Author user id.
  final String? authorUserId;

  /// Avatar url.
  final String? avatarUrl;

  /// Published at text.
  final String? publishedAtText;
}

/// Capabilities exposed by user blog detail.
enum UserBlogDetailCapability {
  /// Stable blog identity.
  stableBlogIdentity,

  /// Stable owner identity.
  stableOwnerIdentity,

  /// Title.
  title,

  /// Body markup.
  bodyMarkup,

  /// Author.
  author,

  /// Avatar reference.
  avatarReference,

  /// Published at text.
  publishedAtText,

  /// View count.
  viewCount,

  /// Comment count.
  commentCount,

  /// Ordered comments.
  orderedComments,

  /// Stable comment identity.
  stableCommentIdentity,

  /// Comment author.
  commentAuthor,

  /// Comment avatar reference.
  commentAvatarReference,

  /// Comment published at text.
  commentPublishedAtText,

  /// Comment body markup.
  commentBodyMarkup,

  /// Commenting availability.
  commentingAvailability,
}

/// Capabilities declared by the user blog detail source.
final class UserBlogDetailSourceCapabilities {
  /// Creates a [UserBlogDetailSourceCapabilities].
  const UserBlogDetailSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<UserBlogDetailCapability> values;

  /// Whether the requested capability is supported.
  bool supports(UserBlogDetailCapability c) => values.supports(c);

  /// Converts this value to read capabilities.
  UserBlogDetailReadCapabilities toReadCapabilities() =>
      UserBlogDetailReadCapabilities(values: values);
}

/// Capabilities effective for one user blog detail read.
final class UserBlogDetailReadCapabilities {
  /// Creates a [UserBlogDetailReadCapabilities].
  const UserBlogDetailReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<UserBlogDetailCapability> values;

  /// Whether the requested capability is supported.
  bool supports(UserBlogDetailCapability c) => values.supports(c);

  /// Returns the conservative intersection with another value.
  UserBlogDetailReadCapabilities intersect(UserBlogDetailReadCapabilities o) =>
      UserBlogDetailReadCapabilities(values: values.intersect(o.values));
}

/// Loads user blog detail data through a source-neutral contract.
abstract interface class UserBlogDetailRepository {
  /// Capabilities declared by this source.
  UserBlogDetailSourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
