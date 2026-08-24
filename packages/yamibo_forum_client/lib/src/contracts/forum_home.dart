import 'cache_load_policy.dart';
import 'data_read_contract.dart';
import 'forum_directory.dart';

enum ForumHomeAudience { automatic, anonymous, authenticated }

final class ForumHomeQuery {
  const ForumHomeQuery({this.audience = ForumHomeAudience.automatic});
  final ForumHomeAudience audience;
}

final class ForumHomeCarouselReference {
  const ForumHomeCarouselReference({
    required this.imageUri,
    required this.targetUri,
  });
  final Uri imageUri;
  final Uri targetUri;
}

final class ForumHomeFavoriteForum {
  const ForumHomeFavoriteForum({
    required this.fid,
    required this.title,
    required this.description,
    required this.todayPosts,
  });
  final String fid;
  final String title;
  final String description;
  final int? todayPosts;
}

final class ForumHomeDocument {
  const ForumHomeDocument({
    required this.directory,
    required this.carousel,
    required this.favoriteForums,
  });
  final ForumDirectoryData directory;
  final List<ForumHomeCarouselReference> carousel;
  final List<ForumHomeFavoriteForum> favoriteForums;
}

enum ForumHomeCapability {
  forumDirectory,
  orderedCarousel,
  stableCarouselTargets,
  favoriteForumProjection,
}

final class ForumHomeSourceCapabilities {
  const ForumHomeSourceCapabilities({required this.values});
  final DataCapabilitySet<ForumHomeCapability> values;
  ForumHomeReadCapabilities toReadCapabilities() =>
      ForumHomeReadCapabilities(values: values);
}

final class ForumHomeReadCapabilities {
  const ForumHomeReadCapabilities({required this.values});
  final DataCapabilitySet<ForumHomeCapability> values;
  bool supports(ForumHomeCapability capability) => values.supports(capability);
  ForumHomeReadCapabilities intersect(ForumHomeReadCapabilities other) =>
      ForumHomeReadCapabilities(values: values.intersect(other.values));
}

final class ForumHomeCachedRead {
  const ForumHomeCachedRead({
    required this.data,
    required this.capabilities,
    required this.metadata,
    required this.updatedAt,
  });
  final ForumHomeDocument data;
  final ForumHomeReadCapabilities capabilities;
  final DataReadMetadata metadata;
  final DateTime updatedAt;
}

abstract interface class ForumHomeRepository {
  ForumHomeSourceCapabilities get homeCapabilities;

  Future<ForumHomeCachedRead?> readCached(ForumHomeQuery query);

  Future<DataReadResult<ForumHomeDocument, ForumHomeReadCapabilities>> loadHome(
    ForumHomeQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
