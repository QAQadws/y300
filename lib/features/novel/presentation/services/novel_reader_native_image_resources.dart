import 'package:flutter/painting.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../models/novel_reader_native_prepared_chapter.dart';

/// A layout request's synchronous resource adapter. It borrows the existing
/// Host/policy; no transport, dimension lookup, image cache or native owner is
/// created here. Only immutable values enter the sequential Session.
final class NovelReaderNativeImageResources {
  const NovelReaderNativeImageResources({
    required this.chapter,
    required this.host,
    required this.policy,
    this.threadId,
    this.cacheOwnerId,
  });
  final NovelReaderNativePreparedChapter chapter;
  final ForumHtmlImageHost? host;
  final ForumHtmlPreparationImagePolicy policy;
  final String? threadId, cacheOwnerId;

  ForumBodyImageInput? resolve(
    ForumBodyIdentity identity,
    ForumBodyElement element,
  ) {
    if (identity != chapter.identity ||
        !identical(chapter.document.nodeAtPath(element.path), element)) {
      throw StateError('Native image source request changed');
    }
    final source = chapter.anchors.imageAtPath(element.path), imageHost = host;
    final reference = element.resource;
    if (source == null ||
        imageHost == null ||
        reference == null ||
        reference.rawSource != source.rawSource) {
      return null;
    }
    final uri = Uri.tryParse(source.url);
    if (uri == null) return null;
    final resource = policy.prepareInline(
      url: uri,
      threadId: threadId,
      imageCacheOwnerId: cacheOwnerId ?? threadId ?? chapter.identity.sourceId,
      imageIndex: source.imageIndex,
      htmlWidth: reference.width,
      htmlHeight: reference.height,
      alt: reference.alt,
      title: reference.title,
    );
    if (resource == null) return null;
    final display = imageHost.resolveImage(
      url: uri,
      imageIndex: source.imageIndex,
      isSticker: false,
      htmlSize: reference.width != null && reference.height != null
          ? Size(reference.width!, reference.height!)
          : null,
    );
    if (display == null ||
        display.sourceUrl != source.url ||
        display.cacheKey != resource.cacheKey ||
        display.isSticker) {
      return null;
    }
    return ForumBodyImageInput(
      identity: identity,
      element: element,
      layout: display.initialLayout,
      entry: ForumHtmlReadableImageEntry(
        index: source.imageIndex,
        url: source.url,
        rawSrc: source.rawSource,
        resource: resource,
        attachmentId: reference.attachmentId,
        alt: reference.alt,
        title: reference.title,
        htmlWidth: reference.width,
        htmlHeight: reference.height,
      ),
    );
  }
}
