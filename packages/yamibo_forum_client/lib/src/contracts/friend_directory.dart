import '../network/forum_request.dart';
import 'cache_load_policy.dart';
import 'data_read_contract.dart';

/// Reads one page of the authenticated user's friends.
final class ForumFriendDirectoryQuery {
  /// Creates a page query, optionally filtered by a username prefix.
  const ForumFriendDirectoryQuery({
    this.page = 1,
    this.username = '',
    this.cancellation,
  });

  /// One-based page number.
  final int page;

  /// Server-side username prefix filter, not a global user search.
  final String username;

  /// Cancels an obsolete page, search, or account read.
  final ForumRequestCancellation? cancellation;
}

/// A friend identity returned by the forum.
final class ForumFriendDirectoryItem {
  /// Creates an identity with an optional validated avatar reference.
  const ForumFriendDirectoryItem({
    required this.userId,
    required this.username,
    this.avatarUrl,
  });

  /// Stable positive forum user ID.
  final String userId;

  /// Exact server username used when selecting a recipient.
  final String username;

  /// Validated HTTP(S) avatar URL, when supplied by the source.
  final String? avatarUrl;
}

/// One network page of the current account's friend directory.
final class ForumFriendDirectoryPage {
  /// Creates a directory page.
  const ForumFriendDirectoryPage({
    required this.items,
    required this.page,
    required this.perPage,
    required this.count,
    this.currentUserId,
  });

  /// Friends in server order.
  final List<ForumFriendDirectoryItem> items;

  /// Current one-based page.
  final int page;

  /// Maximum number of rows on a page.
  final int perPage;

  /// Number of friends matching the prefix.
  final int count;

  /// Response-proven account identity, or null when the source omits it.
  ///
  /// Hosts must still isolate reads by their authenticated account generation.
  final String? currentUserId;

  /// Whether another page can exist according to the server's count.
  bool get hasNext => perPage > 0 && page * perPage < count;
}

/// Capabilities available from a friend source.
enum ForumFriendDirectoryCapability {
  /// Stable forum user IDs and exact usernames.
  identity,

  /// Server-supplied avatar references.
  avatar,

  /// Server-side username prefix filtering.
  usernamePrefix,

  /// Page size and total count.
  paginationSummary,
}

/// Declared friend source capabilities.
final class ForumFriendDirectorySourceCapabilities {
  /// Creates a capability set.
  const ForumFriendDirectorySourceCapabilities({required this.values});

  /// Per-capability support.
  final DataCapabilitySet<ForumFriendDirectoryCapability> values;

  /// Converts declared capabilities to a successful read's capabilities.
  ForumFriendDirectoryReadCapabilities toReadCapabilities() =>
      ForumFriendDirectoryReadCapabilities(values: values);
}

/// Capabilities proven for a successful friend read.
final class ForumFriendDirectoryReadCapabilities {
  /// Creates a capability set.
  const ForumFriendDirectoryReadCapabilities({required this.values});

  /// Per-capability support.
  final DataCapabilitySet<ForumFriendDirectoryCapability> values;
}

/// Loads friends without changing their relationship or reading messages.
abstract interface class ForumFriendDirectoryRepository {
  /// Source-declared capabilities.
  ForumFriendDirectorySourceCapabilities get capabilities;

  /// Loads one page; the standard source does not persist friend data.
  Future<
    DataReadResult<
      ForumFriendDirectoryPage,
      ForumFriendDirectoryReadCapabilities
    >
  >
  load(
    ForumFriendDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
