/// Source-neutral forum directory identities, sections, and capabilities.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';

final class ForumDirectoryQuery {
  const ForumDirectoryQuery();
}

final class ForumDirectoryData {
  const ForumDirectoryData({required this.sections});
  final List<ForumDirectorySection> sections;
}

enum ForumDirectorySectionKind { regular, uncategorized }

final class ForumDirectorySection {
  const ForumDirectorySection({
    required this.identity,
    required this.title,
    required this.forums,
    this.kind = ForumDirectorySectionKind.regular,
  });
  final String identity;
  final String title;
  final List<ForumDirectoryForum> forums;
  final ForumDirectorySectionKind kind;
}

final class ForumDirectoryForum {
  const ForumDirectoryForum({
    required this.fid,
    required this.title,
    required this.description,
    required this.todayPosts,
    this.children = const <ForumDirectoryForum>[],
  });
  final String fid;
  final String title;
  final String description;
  final int? todayPosts;
  final List<ForumDirectoryForum> children;
}

enum ForumDirectoryCapability {
  stableSectionIdentity,
  orderedSections,
  stableForumIdentity,
  orderedForums,
  forumDescription,
  todayPostCount,
  nestedForums,
}

final class ForumDirectorySourceCapabilities {
  const ForumDirectorySourceCapabilities({required this.values});
  final DataCapabilitySet<ForumDirectoryCapability> values;
  bool supports(ForumDirectoryCapability capability) =>
      values.supports(capability);
  ForumDirectoryReadCapabilities toReadCapabilities() =>
      ForumDirectoryReadCapabilities(values: values);
}

final class ForumDirectoryReadCapabilities {
  const ForumDirectoryReadCapabilities({required this.values});
  final DataCapabilitySet<ForumDirectoryCapability> values;
  bool supports(ForumDirectoryCapability capability) =>
      values.supports(capability);
  ForumDirectoryReadCapabilities intersect(
    ForumDirectoryReadCapabilities other,
  ) => ForumDirectoryReadCapabilities(values: values.intersect(other.values));
}

abstract interface class ForumDirectoryRepository {
  ForumDirectorySourceCapabilities get capabilities;
  Future<DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>>
  load(
    ForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
