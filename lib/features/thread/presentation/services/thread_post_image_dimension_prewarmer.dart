import 'dart:async';

import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/presentation/services/thread_post_image_dimension_store.dart';

/// 把"图片块 → 缓存键"的策略与尺寸预热解耦，便于复用页面既有的缓存键规则。
typedef ThreadPostBlockImageCacheKeyResolver =
    String Function(ThreadPostImageBlock image);

/// 在进入阅读态前，用持久化缓存里的真实尺寸预热 [ThreadPostImageDimensionStore]。
///
/// 这样 render plan 能在首帧就拿到可信比例并锁定高度，而不是先用 fallback 占位、
/// 再在滚动中异步 setState 改高（上滑回溯根因）。
///
/// 职责单一：只读缓存、只写 store；不持有 Flutter 依赖、不感知 widget 生命周期。
/// 通过 [seenCacheKeys] 去重，避免对同一图片重复查询缓存。
class ThreadPostImageDimensionPrewarmer {
  ThreadPostImageDimensionPrewarmer({
    required ImageCacheService imageCacheService,
    required ThreadPostImageDimensionStore store,
  }) : _imageCacheService = imageCacheService,
       _store = store;

  final ImageCacheService _imageCacheService;
  final ThreadPostImageDimensionStore _store;
  final Set<String> _seenCacheKeys = <String>{};

  /// 预热一批帖子正文文档中的块级图片尺寸。
  ///
  /// [documents] 与 [cacheKeyResolver] 一起决定查询哪些缓存键；命中后批量写回
  /// store（一次 notify），把多次异步结果合并成尽量少的重建。
  Future<void> prewarmDocuments(
    Iterable<ThreadPostBodyDocument> documents, {
    required ThreadPostBlockImageCacheKeyResolver cacheKeyResolver,
  }) async {
    final pending = <_PendingImage>[];
    for (final document in documents) {
      for (final image in document.images) {
        // HTML 已带宽高的图片无需缓存预热——resolver 会直接用 HTML 尺寸。
        if (_hasHtmlDimension(image)) {
          continue;
        }
        final cacheKey = cacheKeyResolver(image).trim();
        if (cacheKey.isEmpty || !_seenCacheKeys.add(cacheKey)) {
          continue;
        }
        pending.add(
          _PendingImage(
            hintKey: ThreadPostResourceLayoutHints.blockImageKey(image),
            cacheKey: cacheKey,
          ),
        );
      }
    }
    if (pending.isEmpty) {
      return;
    }

    final resolved = <String, ThreadPostResourceDimension>{};
    for (final item in pending) {
      final dimension = await _readDimension(item.cacheKey);
      if (dimension != null) {
        resolved[item.hintKey] = dimension;
      }
    }
    if (resolved.isNotEmpty) {
      _store.recordAll(blockDimensions: resolved);
    }
  }

  Future<ThreadPostResourceDimension?> _readDimension(String cacheKey) async {
    try {
      final result = await _imageCacheService.getCached(cacheKey);
      final width = result?.width;
      final height = result?.height;
      if (width == null || height == null || width <= 0 || height <= 0) {
        return null;
      }
      return ThreadPostResourceDimension(
        width: width.toDouble(),
        height: height.toDouble(),
      );
    } catch (_) {
      // 预热只为改善布局稳定性，缓存读取失败不应影响阅读。
      return null;
    }
  }

  bool _hasHtmlDimension(ThreadPostImageBlock image) {
    final width = image.originalWidth;
    final height = image.originalHeight;
    return width != null &&
        height != null &&
        width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0;
  }
}

class _PendingImage {
  const _PendingImage({required this.hintKey, required this.cacheKey});

  final String hintKey;
  final String cacheKey;
}
