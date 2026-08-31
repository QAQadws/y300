import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_continuous_image_adapter.dart';

enum ThreadHtmlImageReaderBridgeFailureReason {
  sticker,
  emptySequence,
  unmatchedImage,
  invalidInitialIndex,
}

class ThreadHtmlImageReaderBridgeResult {
  const ThreadHtmlImageReaderBridgeResult.open(this.request)
    : failureReason = null;

  const ThreadHtmlImageReaderBridgeResult.fallback(this.failureReason)
    : request = null;

  final ThreadPostImageOpenRequest? request;
  final ThreadHtmlImageReaderBridgeFailureReason? failureReason;

  bool get canOpen => request != null;
}

class ThreadHtmlImageReaderBridge {
  const ThreadHtmlImageReaderBridge({
    ThreadImageReaderContinuousImageAdapter readerAdapter =
        const ThreadImageReaderContinuousImageAdapter(),
  }) : _readerAdapter = readerAdapter;

  final ThreadImageReaderContinuousImageAdapter _readerAdapter;

  ThreadHtmlImageReaderBridgeResult buildOpenRequest({
    required ThreadPost post,
    required String threadId,
    required String imageReferer,
    required ThreadPostBodyRenderPlan legacyPlan,
    required ForumHtmlReadableImageSequence sequence,
    required ForumHtmlImageRequest imageRequest,
  }) {
    if (imageRequest.isSticker) {
      return const ThreadHtmlImageReaderBridgeResult.fallback(
        ThreadHtmlImageReaderBridgeFailureReason.sticker,
      );
    }
    if (sequence.entries.isEmpty) {
      return const ThreadHtmlImageReaderBridgeResult.fallback(
        ThreadHtmlImageReaderBridgeFailureReason.emptySequence,
      );
    }

    final entry = _resolveEntry(
      sequence: sequence,
      imageRequest: imageRequest,
      legacyPlan: legacyPlan,
    );
    if (entry == null) {
      return const ThreadHtmlImageReaderBridgeResult.fallback(
        ThreadHtmlImageReaderBridgeFailureReason.unmatchedImage,
      );
    }

    final images = _imageBlocksFor(sequence);
    final entries = sequence.entries
        .map(_readerEntryFor)
        .toList(growable: false);
    final initialIndex = entry.index;
    if (initialIndex < 0 || initialIndex >= entries.length) {
      return const ThreadHtmlImageReaderBridgeResult.fallback(
        ThreadHtmlImageReaderBridgeFailureReason.invalidInitialIndex,
      );
    }

    final group = ThreadPostImageGroup(
      tid: threadId,
      pid: post.pid,
      postNumber: post.number,
      entries: entries,
    );
    final readerRequest = ThreadImageOpenRequest(
      tid: threadId,
      pid: post.pid,
      postNumber: post.number,
      referer: imageReferer,
      group: group,
      initialIndex: initialIndex,
    );

    return ThreadHtmlImageReaderBridgeResult.open(
      ThreadPostImageOpenRequest(
        document: RichDocument(blocks: images),
        images: images,
        image: images[initialIndex],
        initialIndex: initialIndex,
        readerRequest: ThreadImageOpenRequest(
          tid: readerRequest.tid,
          pid: readerRequest.pid,
          postNumber: readerRequest.postNumber,
          referer: readerRequest.referer,
          group: readerRequest.group,
          initialIndex: readerRequest.initialIndex,
          continuousImages: _readerAdapter.mapRequest(readerRequest),
        ),
      ),
    );
  }

  ForumHtmlReadableImageEntry? _resolveEntry({
    required ForumHtmlReadableImageSequence sequence,
    required ForumHtmlImageRequest imageRequest,
    required ThreadPostBodyRenderPlan legacyPlan,
  }) {
    final readableIndex = imageRequest.readableIndex;
    if (readableIndex != null) {
      return sequence.entryAt(readableIndex);
    }

    final attachmentId = imageRequest.attachmentId?.trim();
    if (attachmentId != null && attachmentId.isNotEmpty) {
      for (final entry in sequence.entries) {
        if (entry.attachmentId?.trim() == attachmentId) {
          return entry;
        }
      }
    }

    final legacyMatch = _matchLegacyImage(imageRequest, legacyPlan.images);
    if (legacyMatch != null) {
      final legacyUrl = _normalizeUrlForMatch(legacyMatch.url);
      final legacyRawUrl = _normalizeUrlForMatch(legacyMatch.rawUrl);
      for (final entry in sequence.entries) {
        final url = _normalizeUrlForMatch(entry.url);
        if (url == legacyUrl || url == legacyRawUrl) {
          return entry;
        }
      }
    }

    final requestUrl = _normalizeUrlForMatch(imageRequest.url);
    for (final entry in sequence.entries) {
      if (_normalizeUrlForMatch(entry.url) == requestUrl ||
          _normalizeUrlForMatch(entry.rawSrc) == requestUrl) {
        return entry;
      }
    }
    return null;
  }

  RichImageBlock? _matchLegacyImage(
    ForumHtmlImageRequest request,
    List<RichImageBlock> images,
  ) {
    final attachmentId = request.attachmentId?.trim();
    if (attachmentId != null && attachmentId.isNotEmpty) {
      for (final image in images) {
        if (image.aid?.trim() == attachmentId) {
          return image;
        }
      }
    }
    final requestUrl = _normalizeUrlForMatch(request.url);
    for (final image in images) {
      if (_normalizeUrlForMatch(image.url) == requestUrl ||
          _normalizeUrlForMatch(image.rawUrl) == requestUrl) {
        return image;
      }
    }
    return null;
  }

  List<RichImageBlock> _imageBlocksFor(
    ForumHtmlReadableImageSequence sequence,
  ) {
    return sequence.entries
        .map((entry) {
          return RichImageBlock(
            anchorId: 'html-first-image-${entry.index}',
            url: entry.url,
            rawUrl: entry.rawSrc,
            index: entry.index,
            aid: entry.attachmentId,
            altText: entry.alt,
            originalWidth: entry.htmlWidth,
            originalHeight: entry.htmlHeight,
          );
        })
        .toList(growable: false);
  }

  ThreadPostImageEntry _readerEntryFor(ForumHtmlReadableImageEntry entry) {
    return ThreadPostImageEntry(
      url: entry.url,
      rawUrl: entry.rawSrc,
      indexInPost: entry.index,
      cacheKey: entry.cacheKey,
      aid: entry.attachmentId,
      layoutHint: _layoutHintFor(entry),
    );
  }

  ThreadPostBlockImageLayoutHint? _layoutHintFor(
    ForumHtmlReadableImageEntry entry,
  ) {
    final width = entry.htmlWidth;
    final height = entry.htmlHeight;
    if (width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    return ThreadPostBlockImageLayoutHint(
      aspectRatio: width / height,
      source: ThreadPostResourceLayoutHintSource.htmlAttribute,
      lockForCurrentBuild: false,
    );
  }

  String _normalizeUrlForMatch(String value) {
    final trimmed = value.trim();
    final resolved = ForumHtmlWidgetPostRenderer.forumBaseUri.resolve(trimmed);
    return resolved.removeFragment().toString();
  }
}
