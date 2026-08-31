/// Source-neutral forum directory identities, sections, and capabilities.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';

/// Query parameters for forum directory.
final class ForumDirectoryQuery {
  /// Creates a [ForumDirectoryQuery].
  const ForumDirectoryQuery();
}

/// Source-neutral forum directory data.
final class ForumDirectoryData {
  /// Creates a [ForumDirectoryData].
  const ForumDirectoryData({required this.sections});

  /// Sections.
  final List<ForumDirectorySection> sections;
}

/// Values describing forum directory section kind.
enum ForumDirectorySectionKind {
  /// Regular.
  regular,

  /// Uncategorized.
  uncategorized,
}

/// Source-neutral forum directory section.
final class ForumDirectorySection {
  /// Creates a [ForumDirectorySection].
  const ForumDirectorySection({
    required this.identity,
    required this.title,
    required this.forums,
    this.kind = ForumDirectorySectionKind.regular,
  });

  /// Identity.
  final String identity;

  /// Title.
  final String title;

  /// Forums.
  final List<ForumDirectoryForum> forums;

  /// Structured kind for this value.
  final ForumDirectorySectionKind kind;
}

/// Source-neutral forum directory forum.
final class ForumDirectoryForum {
  /// Creates a [ForumDirectoryForum].
  const ForumDirectoryForum({
    required this.fid,
    required this.title,
    required this.description,
    required this.todayPosts,
    this.children = const <ForumDirectoryForum>[],
  });

  /// Stable forum identifier.
  final String fid;

  /// Title.
  final String title;

  /// Description.
  final String description;

  /// Today posts.
  final int? todayPosts;

  /// Children.
  final List<ForumDirectoryForum> children;
}

/// Capabilities exposed by forum directory.
enum ForumDirectoryCapability {
  /// Stable section identity.
  stableSectionIdentity,

  /// Ordered sections.
  orderedSections,

  /// Stable forum identity.
  stableForumIdentity,

  /// Ordered forums.
  orderedForums,

  /// Forum description.
  forumDescription,

  /// Today post count.
  todayPostCount,

  /// Nested forums.
  nestedForums,
}

/// Capabilities declared by the forum directory source.
final class ForumDirectorySourceCapabilities {
  /// Creates a [ForumDirectorySourceCapabilities].
  const ForumDirectorySourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumDirectoryCapability> values;

  /// Whether the requested capability is supported.
  bool supports(ForumDirectoryCapability capability) =>
      values.supports(capability);

  /// Converts this value to read capabilities.
  ForumDirectoryReadCapabilities toReadCapabilities() =>
      ForumDirectoryReadCapabilities(values: values);
}

/// Capabilities effective for one forum directory read.
final class ForumDirectoryReadCapabilities {
  /// Creates a [ForumDirectoryReadCapabilities].
  const ForumDirectoryReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumDirectoryCapability> values;

  /// Whether the requested capability is supported.
  bool supports(ForumDirectoryCapability capability) =>
      values.supports(capability);

  /// Returns the conservative intersection with another value.
  ForumDirectoryReadCapabilities intersect(
    ForumDirectoryReadCapabilities other,
  ) => ForumDirectoryReadCapabilities(values: values.intersect(other.values));
}

/// Loads forum directory data through a source-neutral contract.
abstract interface class ForumDirectoryRepository {
  /// Capabilities declared by this source.
  ForumDirectorySourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>>
  load(
    ForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
