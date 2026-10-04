import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';

/// Host ownership for prepared readable images; this port stays isolate-safe.
/// The Host supplies kind, owner, protection and display hints. Preparation
/// preserves that spec and fills cache identity/retention through the resolver.
abstract interface class ForumHtmlPreparationImagePolicy {
  ForumImageLoadSpec inlineSpec({
    required Uri url,
    required String? threadId,
    required String? imageCacheOwnerId,
    required int imageIndex,
    double? htmlWidth,
    double? htmlHeight,
    String? alt,
    String? title,
  });
}
