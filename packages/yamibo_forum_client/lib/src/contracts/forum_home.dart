/// Read contract for the combined forum home document and cached projection.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';
import 'forum_directory.dart';

/// Values describing forum home audience.
enum ForumHomeAudience {
  /// Automatic.
  automatic,

  /// Anonymous.
  anonymous,

  /// Authenticated.
  authenticated,
}

/// Query parameters for forum home.
final class ForumHomeQuery {
  /// Creates a [ForumHomeQuery].
  const ForumHomeQuery({this.audience = ForumHomeAudience.automatic});

  /// Audience.
  final ForumHomeAudience audience;
}

/// Source-neutral forum home carousel reference.
final class ForumHomeCarouselReference {
  /// Creates a [ForumHomeCarouselReference].
  const ForumHomeCarouselReference({
    required this.imageUri,
    required this.targetUri,
  });

  /// Image uri.
  final Uri imageUri;

  /// Target uri.
  final Uri targetUri;
}

/// Source-neutral forum home favorite forum.
final class ForumHomeFavoriteForum {
  /// Creates a [ForumHomeFavoriteForum].
  const ForumHomeFavoriteForum({
    required this.fid,
    required this.title,
    required this.description,
    required this.todayPosts,
  });

  /// Stable forum identifier.
  final String fid;

  /// Title.
  final String title;

  /// Description.
  final String description;

  /// Today posts.
  final int? todayPosts;
}

/// Source-neutral forum home document.
final class ForumHomeDocument {
  /// Creates a [ForumHomeDocument].
  const ForumHomeDocument({
    required this.directory,
    required this.carousel,
    required this.favoriteForums,
  });

  /// Directory.
  final ForumDirectoryData directory;

  /// Carousel.
  final List<ForumHomeCarouselReference> carousel;

  /// Favorite forums.
  final List<ForumHomeFavoriteForum> favoriteForums;
}

/// Capabilities exposed by forum home.
enum ForumHomeCapability {
  /// Forum directory.
  forumDirectory,

  /// Ordered carousel.
  orderedCarousel,

  /// Stable carousel targets.
  stableCarouselTargets,

  /// Favorite forum projection.
  favoriteForumProjection,
}

/// Capabilities declared by the forum home source.
final class ForumHomeSourceCapabilities {
  /// Creates a [ForumHomeSourceCapabilities].
  const ForumHomeSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumHomeCapability> values;

  /// Converts this value to read capabilities.
  ForumHomeReadCapabilities toReadCapabilities() =>
      ForumHomeReadCapabilities(values: values);
}

/// Capabilities effective for one forum home read.
final class ForumHomeReadCapabilities {
  /// Creates a [ForumHomeReadCapabilities].
  const ForumHomeReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumHomeCapability> values;

  /// Whether the requested capability is supported.
  bool supports(ForumHomeCapability capability) => values.supports(capability);

  /// Returns the conservative intersection with another value.
  ForumHomeReadCapabilities intersect(ForumHomeReadCapabilities other) =>
      ForumHomeReadCapabilities(values: values.intersect(other.values));
}

/// Source-neutral forum home cached read.
final class ForumHomeCachedRead {
  /// Creates a [ForumHomeCachedRead].
  const ForumHomeCachedRead({
    required this.data,
    required this.capabilities,
    required this.metadata,
    required this.updatedAt,
  });

  /// Source-neutral business payload.
  final ForumHomeDocument data;

  /// Capabilities proven by the selected source.
  final ForumHomeReadCapabilities capabilities;

  /// Origin and freshness metadata for the read.
  final DataReadMetadata metadata;

  /// Updated at.
  final DateTime updatedAt;
}

/// Loads forum home data through a source-neutral contract.
abstract interface class ForumHomeRepository {
  /// Capabilities declared by the cached home source.
  ForumHomeSourceCapabilities get homeCapabilities;

  /// Reads the current cached home document without forcing a network request.
  Future<ForumHomeCachedRead?> readCached(ForumHomeQuery query);

  /// Loads home and returns a structured result.
  Future<DataReadResult<ForumHomeDocument, ForumHomeReadCapabilities>> loadHome(
    ForumHomeQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
