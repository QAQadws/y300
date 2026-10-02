import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';

/// Immutable snapshot of one rendered article or comment, never a whole feed.
final class BlogImageReaderRequest {
  BlogImageReaderRequest._(this.items, this.requests, this.initialIndex);

  final List<ContinuousImageItem> items;
  final List<ImageCacheRequest> requests;
  final int initialIndex;

  static BlogImageReaderRequest? fromImage({
    required ForumHtmlReadableImageSequence sequence,
    required ForumHtmlImageRequest image,
    required String cacheOwnerId,
    required String sessionOwnerId,
    required String referer,
    required ForumImageRequestResolver resolver,
  }) {
    if (image.isSticker || sequence.entries.isEmpty) return null;
    final selectedUri = _uri(image.url);
    if (selectedUri == null) return null;
    final selected =
        image.readableIndex ??
        sequence.entries.indexWhere((entry) => _uri(entry.url) == selectedUri);
    if (selected < 0 ||
        selected >= sequence.entries.length ||
        _uri(sequence.entries[selected].url) != selectedUri) {
      return null;
    }
    final requests = <ImageCacheRequest>[];
    final items = <ContinuousImageItem>[];
    for (final entry in sequence.entries) {
      final uri = _uri(entry.url);
      if (uri == null) return null;
      // Prepared HTML also serves thread readers; its stored cache keys and
      // owner types are not the blog display policy. Resolve the same blog
      // specification as the inline widget so opening never creates a copy.
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.blogInline,
          url: uri,
          ownerId: cacheOwnerId,
          ownerType: ImageCacheOwnerType.blog,
          referer: referer,
          imageIndex: items.length,
        ),
      );
      if (request == null) return null;
      requests.add(request);
      final width = _dimension(entry.htmlWidth);
      final height = _dimension(entry.htmlHeight);
      items.add(
        ContinuousImageItem(
          ownerId: sessionOwnerId,
          id: '$sessionOwnerId:${items.length}',
          url: request.sourceUrl,
          cacheKey: request.cacheKey,
          index: items.length,
          sourceKind: ContinuousImageSourceKind.genericImageReader,
          referer: Uri.tryParse(referer),
          knownWidth: width,
          knownHeight: height,
          knownDimensionSource: width != null && height != null
              ? ContinuousImageDimensionSource.html
              : null,
        ),
      );
    }
    if (image.cacheKey != null &&
        image.cacheKey != requests[selected].cacheKey) {
      return null;
    }
    return BlogImageReaderRequest._(
      List.unmodifiable(items),
      List.unmodifiable(requests),
      selected,
    );
  }

  static Uri? _uri(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
            {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri.removeFragment()
        : null;
  }

  static int? _dimension(double? value) =>
      value != null && value.isFinite && value >= 1 && value < 2147483647
      ? value.round()
      : null;
}
