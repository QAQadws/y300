import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

enum FavoriteDetailCapability {
  stableThreadIdentity,
  forumClassification,
  orderedPosts,
  renderableBody,
  attachmentMetadata,
}

final class FavoriteDetailReadCapabilities {
  const FavoriteDetailReadCapabilities(this.values);

  final DataCapabilitySet<FavoriteDetailCapability> values;

  bool supports(FavoriteDetailCapability capability) {
    return values.supports(capability);
  }
}

class FavoriteDetailContext {
  const FavoriteDetailContext({
    required this.record,
    required this.detail,
    required this.kind,
    this.tagName,
  });

  final FavoriteThreadCacheRecord record;
  final ThreadDetailData detail;
  final ThreadContentKind kind;
  final String? tagName;
}

sealed class FavoriteDetailResolution {
  const FavoriteDetailResolution();
}

class ResolvedFavoriteDetail extends FavoriteDetailResolution {
  const ResolvedFavoriteDetail(this.context);

  final FavoriteDetailContext context;
}

class InvalidFavoriteDetail extends FavoriteDetailResolution {
  const InvalidFavoriteDetail({required this.record, required this.detail});

  final FavoriteThreadCacheRecord record;
  final ThreadDetailData detail;
}
