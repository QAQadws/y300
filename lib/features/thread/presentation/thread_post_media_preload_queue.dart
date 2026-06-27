import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:y300/features/cache/domain/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_document_normalizer.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_parser.dart';

class ThreadPostMediaPreloadQueue {
  ThreadPostMediaPreloadQueue({
    required ImageCacheService imageCacheService,
    ThreadPostBodyParser parser = const ThreadPostBodyParser(),
    ThreadPostBodyDocumentNormalizer normalizer =
        const ThreadPostBodyDocumentNormalizer(),
    this.maxConcurrent = 2,
  }) : _imageCacheService = imageCacheService,
       _parser = parser,
       _normalizer = normalizer;

  final ImageCacheService _imageCacheService;
  final ThreadPostBodyParser _parser;
  final ThreadPostBodyDocumentNormalizer _normalizer;
  final int maxConcurrent;

  final Set<String> _queuedOrDone = <String>{};
  final List<ImageCacheRequest> _pending = <ImageCacheRequest>[];
  var _running = 0;
  var _disposed = false;

  void dispose() {
    _disposed = true;
    _pending.clear();
    _queuedOrDone.clear();
  }

  void preloadNearbyPosts({
    required String tid,
    required List<ThreadPost> posts,
    required int centerIndex,
    int radius = 2,
  }) {
    if (_disposed || posts.isEmpty) {
      return;
    }
    final start = (centerIndex - radius).clamp(0, posts.length - 1);
    final end = (centerIndex + radius).clamp(0, posts.length - 1);
    for (var index = start; index <= end; index += 1) {
      _enqueuePost(tid: tid, post: posts[index]);
    }
    _pump();
  }

  void _enqueuePost({required String tid, required ThreadPost post}) {
    final document = _normalizer.normalize(_parser.parse(post.message));
    for (final request in _requestsForDocument(tid: tid, document: document)) {
      final key = request.cacheKey.trim();
      if (key.isEmpty || !_queuedOrDone.add(key)) {
        continue;
      }
      _pending.add(request);
    }
  }

  Iterable<ImageCacheRequest> _requestsForDocument({
    required String tid,
    required ThreadPostBodyDocument document,
  }) sync* {
    for (final block in document.blocks) {
      yield* _requestsForBlock(tid: tid, block: block);
    }
  }

  Iterable<ImageCacheRequest> _requestsForBlock({
    required String tid,
    required ThreadPostBodyBlock block,
  }) sync* {
    if (block is ThreadPostImageBlock) {
      yield ForumImageCacheRequests.threadInline(
        tid: tid,
        url: block.url,
        imageIndex: block.index,
      );
      return;
    }
    if (block is ThreadPostTextBlock) {
      for (final run in block.runs) {
        final image = run.inlineImage;
        if (image != null) {
          yield ForumImageCacheRequests.remoteSmiley(url: image.url);
        }
      }
      return;
    }
    if (block is ThreadPostQuoteBlock) {
      for (final child in block.blocks) {
        yield* _requestsForBlock(tid: tid, block: child);
      }
    }
  }

  void _pump() {
    if (_disposed) {
      return;
    }
    while (_running < maxConcurrent && _pending.isNotEmpty) {
      final request = _pending.removeAt(0);
      _running += 1;
      unawaited(
        _preload(request).whenComplete(() {
          _running -= 1;
          _pump();
        }),
      );
    }
  }

  Future<void> _preload(ImageCacheRequest request) async {
    final result = await _imageCacheService.ensureCached(request);
    if (!result.success ||
        (result.width != null && result.height != null) ||
        result.localPath == null ||
        _imageCacheService is! ImageCacheDimensionRecorder) {
      return;
    }
    final recorder = _imageCacheService as ImageCacheDimensionRecorder;
    final file = io.File(result.localPath!);
    if (!await file.exists()) {
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      final image = await _decodeImage(bytes);
      try {
        await recorder.recordResolvedDimensions(
          cacheKey: request.cacheKey,
          size: ui.Size(image.width.toDouble(), image.height.toDouble()),
        );
      } finally {
        image.dispose();
      }
    } catch (_) {
      // Preloading improves future layout hints only. A failed decode should not
      // block normal image rendering.
    }
  }

  Future<ui.Image> _decodeImage(List<int> bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(Uint8List.fromList(bytes), completer.complete);
    return completer.future;
  }
}
