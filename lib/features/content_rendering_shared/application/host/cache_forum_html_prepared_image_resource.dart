import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/content_rendering_shared/presentation/contracts/forum_html_prepared_image_resource.dart';

/// Keeps the complete cache binding outside the prepared-document contract.
final class CacheForumHtmlPreparedImageResource
    implements ForumHtmlPreparedImageResource {
  const CacheForumHtmlPreparedImageResource._({
    required this.spec,
    required this.request,
  });

  final ForumImageLoadSpec spec;
  final ImageCacheRequest request;

  @override
  String get cacheKey => request.cacheKey;

  static CacheForumHtmlPreparedImageResource? prepare(
    ForumImageLoadSpec spec, {
    ForumImageRequestResolver imageRequestResolver =
        const DefaultForumImageRequestResolver(),
  }) {
    final request = imageRequestResolver.resolveCacheRequest(spec);
    if (request == null) {
      return null;
    }
    return CacheForumHtmlPreparedImageResource._(
      spec: ForumImageLoadSpec(
        kind: spec.kind,
        url: spec.url,
        referer: spec.referer,
        ownerId: spec.ownerId,
        ownerType: spec.ownerType,
        episodeId: spec.episodeId,
        imageIndex: spec.imageIndex,
        cacheKey: request.cacheKey,
        retentionClass: request.retentionClass,
        htmlWidth: spec.htmlWidth,
        htmlHeight: spec.htmlHeight,
        displayWidth: spec.displayWidth,
        displayHeight: spec.displayHeight,
        alt: spec.alt,
        title: spec.title,
        protected: spec.protected,
        allowReaderOpen: spec.allowReaderOpen,
      ),
      request: request,
    );
  }
}
