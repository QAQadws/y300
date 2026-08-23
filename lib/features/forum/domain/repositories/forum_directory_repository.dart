import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/forum/domain/models/forum_directory_models.dart';

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

  bool supports(ForumDirectoryCapability capability) {
    return values.supports(capability);
  }

  ForumDirectoryReadCapabilities toReadCapabilities() {
    return ForumDirectoryReadCapabilities(values: values);
  }
}

final class ForumDirectoryReadCapabilities {
  const ForumDirectoryReadCapabilities({required this.values});

  final DataCapabilitySet<ForumDirectoryCapability> values;

  bool supports(ForumDirectoryCapability capability) {
    return values.supports(capability);
  }

  ForumDirectoryReadCapabilities intersect(
    ForumDirectoryReadCapabilities other,
  ) {
    return ForumDirectoryReadCapabilities(
      values: values.intersect(other.values),
    );
  }
}

abstract interface class ForumDirectoryRepository {
  ForumDirectorySourceCapabilities get capabilities;

  Future<DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>>
  load(
    ForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
