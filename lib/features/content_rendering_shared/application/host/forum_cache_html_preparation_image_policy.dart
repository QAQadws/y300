import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/content_rendering_shared/application/host/cache_forum_html_prepared_image_resource.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

/// Keeps the existing prepared-document cache identity, including novel HTML.
final class ForumCacheHtmlPreparationImagePolicy
    implements ForumHtmlPreparationImagePolicy {
  const ForumCacheHtmlPreparationImagePolicy({
    this.imageRequestResolver = const DefaultForumImageRequestResolver(),
  });

  final ForumImageRequestResolver imageRequestResolver;

  @override
  CacheForumHtmlPreparedImageResource? prepareInline({
    required Uri url,
    required String? threadId,
    required String? imageCacheOwnerId,
    required int imageIndex,
    double? htmlWidth,
    double? htmlHeight,
    String? alt,
    String? title,
  }) => CacheForumHtmlPreparedImageResource.prepare(
    ForumImageLoadSpec(
      kind: ForumImageKind.threadInline,
      url: url,
      ownerId: _ownerId(
        threadId: threadId,
        imageCacheOwnerId: imageCacheOwnerId,
      ),
      ownerType: ImageCacheOwnerType.thread,
      imageIndex: imageIndex,
      htmlWidth: htmlWidth,
      htmlHeight: htmlHeight,
      alt: alt,
      title: title,
      allowReaderOpen: true,
    ),
    imageRequestResolver: imageRequestResolver,
  );
  String _ownerId({
    required String? threadId,
    required String? imageCacheOwnerId,
  }) {
    final owner = imageCacheOwnerId?.trim();
    if (owner != null && owner.isNotEmpty) {
      return owner;
    }
    final tid = threadId?.trim();
    return tid == null || tid.isEmpty ? 'unknown' : tid;
  }
}
