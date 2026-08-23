import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/tags/domain/models/forum_tag_directory_models.dart';

enum ForumTagDirectoryCapability {
  stableTagIdentity,
  orderedTopics,
  stableTopicIdentity,
  topicTitle,
  tagName,
  topicForum,
  topicAuthor,
  topicCreationTime,
  topicReplyCount,
  topicViewCount,
  topicLastPost,
  topicAttachmentFlags,
  directionalPagination,
  totalPageCount,
}

final class ForumTagDirectorySourceCapabilities {
  const ForumTagDirectorySourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<ForumTagDirectoryCapability> values;
  final PaginationPrecision paginationPrecision;

  bool supports(ForumTagDirectoryCapability capability) {
    return values.supports(capability);
  }

  ForumTagDirectoryReadCapabilities toReadCapabilities() {
    return ForumTagDirectoryReadCapabilities(
      values: values,
      paginationPrecision: paginationPrecision,
    );
  }
}

final class ForumTagDirectoryReadCapabilities {
  const ForumTagDirectoryReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<ForumTagDirectoryCapability> values;
  final PaginationPrecision paginationPrecision;

  bool supports(ForumTagDirectoryCapability capability) {
    return values.supports(capability);
  }

  ForumTagDirectoryReadCapabilities intersect(
    ForumTagDirectoryReadCapabilities other,
  ) {
    return ForumTagDirectoryReadCapabilities(
      values: values.intersect(other.values),
      paginationPrecision: paginationPrecision.intersect(
        other.paginationPrecision,
      ),
    );
  }
}

abstract interface class ForumTagDirectoryRepository {
  ForumTagDirectorySourceCapabilities get capabilities;

  Future<
    DataReadResult<ForumTagDirectoryData, ForumTagDirectoryReadCapabilities>
  >
  load(
    ForumTagDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
