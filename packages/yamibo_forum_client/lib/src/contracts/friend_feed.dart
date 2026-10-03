import '../network/forum_request.dart';
import 'cache_load_policy.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';

/// The account's four member lists shown by the forum's touch friend page.
enum ForumFriendFeedScope {
  /// Established friends of the authenticated account.
  friends,

  /// Visible online members, including members who are not friends.
  online,

  /// Members who recently visited the authenticated account's space.
  visitors,

  /// Spaces recently visited by the authenticated account.
  footprints,
}

/// One account-bound, network-only member list query.
final class ForumFriendFeedQuery {
  /// Creates a query for an explicitly authenticated account.
  const ForumFriendFeedQuery({
    required this.accountUserId,
    this.scope = ForumFriendFeedScope.friends,
    this.page = 1,
    this.cancellation,
  });

  /// Expected authenticated account; this is never a public space owner query.
  final String accountUserId;

  /// Member list to read.
  final ForumFriendFeedScope scope;

  /// One-based server page.
  final int page;

  /// Cancellation of an obsolete account or page read.
  final ForumRequestCancellation? cancellation;
}

/// A member identity and optional server-proven friend-page details.
final class ForumFriendFeedItem {
  /// Creates one member row.
  const ForumFriendFeedItem({
    required this.userId,
    required this.username,
    this.profileUrl,
    this.avatarUrl,
    this.note,
    this.visitedAtText,
    this.isOnline,
    this.canRemove = false,
  });

  /// Stable positive member identity, or empty for an anonymous visitor.
  final String userId;

  /// Exact server display name, or empty for an anonymous visitor.
  final String username;

  /// Source-proven member-profile link resolved against the managed origin.
  ///
  /// Preserves the original query and fragment. Null for anonymous rows or
  /// sources without a proved link; Hosts must not synthesize one from [userId].
  final String? profileUrl;

  /// Validated HTTP(S) avatar reference, when provided.
  final String? avatarUrl;

  /// Server recent status or member note, when supplied.
  final String? note;

  /// Server-formatted visit time; omitted when the touch template lacks it.
  final String? visitedAtText;

  /// Presence proved by the selected list or an explicit online marker.
  final bool? isOnline;

  /// Whether this row exposes the forum's friend-removal action.
  final bool canRemove;
}

/// One verified page of the current account's member list.
final class ForumFriendFeedPage {
  /// Creates an account-bound page with conservative pagination.
  const ForumFriendFeedPage({
    required this.scope,
    required this.currentUserId,
    required this.items,
    required this.page,
    this.hasNext = false,
    this.totalPages,
    this.count,
  });

  /// Member list represented by this page.
  final ForumFriendFeedScope scope;

  /// Authenticated identity proved by the response header.
  final String currentUserId;

  /// Member rows in server order.
  final List<ForumFriendFeedItem> items;

  /// One-based server page.
  final int page;

  /// Whether the server exposes a following page in the same list.
  final bool hasNext;

  /// Exact total pages when the server includes a total-page control.
  final int? totalPages;

  /// Exact matching member count, if supplied by the source.
  final int? count;
}

/// Optional friend-list details available from a source.
enum ForumFriendFeedCapability {
  /// Member identities and names.
  identity,

  /// Server avatar references.
  avatar,

  /// Recent member status.
  note,

  /// Presence markers.
  onlineStatus,

  /// Server-formatted visit times.
  visitedAtText,

  /// Server-proven next-page links.
  pagination,

  /// Friend-removal actions.
  removal,
}

/// Capabilities declared by a member-list source.
final class ForumFriendFeedSourceCapabilities {
  /// Creates a declared capability set.
  const ForumFriendFeedSourceCapabilities({required this.values});

  /// Per-detail source support.
  final DataCapabilitySet<ForumFriendFeedCapability> values;
}

/// Capabilities proved for one successful member-list read.
final class ForumFriendFeedReadCapabilities {
  /// Creates a response-proven capability set.
  const ForumFriendFeedReadCapabilities({required this.values});

  /// Per-detail support in this response.
  final DataCapabilitySet<ForumFriendFeedCapability> values;
}

/// Reads friend-page lists without persisting private account data.
abstract interface class ForumFriendFeedRepository {
  /// Declared member-list capabilities.
  ForumFriendFeedSourceCapabilities get capabilities;

  /// Loads one list page; standard sources always use the network.
  Future<DataReadResult<ForumFriendFeedPage, ForumFriendFeedReadCapabilities>>
  load(
    ForumFriendFeedQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

/// One explicit friend-removal request from the current account.
final class ForumFriendRemovalSubmission {
  /// Creates a removal with distinct actor and target identities.
  const ForumFriendRemovalSubmission({
    required this.actorUserId,
    required this.userId,
    this.cancellation,
  });

  /// Authenticated account that removes the relationship.
  final String actorUserId;

  /// Friend identity being removed.
  final String userId;

  /// Cancellation of an obsolete account command.
  final ForumRequestCancellation? cancellation;
}

/// Server-confirmed removal of the requested friend relationship.
final class ForumFriendRemovalReceipt {
  /// Creates a receipt after verifying the server's target callback.
  const ForumFriendRemovalReceipt({
    required this.actorUserId,
    required this.userId,
  });

  /// Authenticated account that performed the removal.
  final String actorUserId;

  /// Removed friend identity.
  final String userId;
}

/// Prepares and sends a single friend removal without automatic mutation retry.
abstract interface class ForumFriendRemovalCommand {
  /// Returns applied only for an exact success callback for the requested user.
  Future<DataCommandResult<ForumFriendRemovalReceipt>> execute(
    ForumFriendRemovalSubmission submission,
  );
}
