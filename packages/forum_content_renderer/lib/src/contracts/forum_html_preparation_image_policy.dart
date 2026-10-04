import 'forum_html_prepared_image_resource.dart';

/// Host ownership for prepared readable images; this port stays isolate-safe.
/// The Host resolves and preserves its complete resource binding. Preparation
/// consumes its identity only; null rejects this image from the readable list.
abstract interface class ForumHtmlPreparationImagePolicy {
  ForumHtmlPreparedImageResource? prepareInline({
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
