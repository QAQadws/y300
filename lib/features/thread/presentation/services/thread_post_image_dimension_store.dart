import 'package:flutter/foundation.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/domain/services/thread_post_resource_layout_hint_resolver.dart';

/// 表现层持有的、可增量填充的图片真实尺寸快照。
///
/// 实现领域接口 [ThreadPostImageDimensionLookup]：render plan 装配时同步读取，
/// [ThreadPostImageDimensionPrewarmer] 异步写入。每次写入推进 [signature]，
/// 使依赖它的 render plan 缓存失效并以"锁定的可信尺寸"重新装配，从而首帧定高、
/// 避免滚动中异步改高造成的上滑回溯。
///
/// 设计取舍：本类不感知缓存键策略（由 prewarmer 负责），只按
/// [ThreadPostResourceLayoutHints.blockImageKey] / `inlineImageKey` 存取，
/// 与 resolver 的查询口径保持一致。
class ThreadPostImageDimensionStore extends ChangeNotifier
    implements ThreadPostImageDimensionLookup {
  final Map<String, ThreadPostResourceDimension> _blockDimensions =
      <String, ThreadPostResourceDimension>{};
  final Map<String, ThreadPostResourceDimension> _inlineDimensions =
      <String, ThreadPostResourceDimension>{};

  int _revision = 0;
  bool _disposed = false;

  @override
  String get signature => 'rev:$_revision';

  @override
  ThreadPostResourceDimension? blockImageDimension(ThreadPostImageBlock image) {
    return _blockDimensions[ThreadPostResourceLayoutHints.blockImageKey(image)];
  }

  @override
  ThreadPostResourceDimension? inlineImageDimension(
    ThreadPostInlineImage image,
  ) {
    return _inlineDimensions[ThreadPostResourceLayoutHints.inlineImageKey(
      image,
    )];
  }

  /// 批量写入一组尺寸；仅在确有新增/变化时推进 revision 并通知，避免无谓重建。
  void recordAll({
    Map<String, ThreadPostResourceDimension> blockDimensions =
        const <String, ThreadPostResourceDimension>{},
    Map<String, ThreadPostResourceDimension> inlineDimensions =
        const <String, ThreadPostResourceDimension>{},
  }) {
    // Cache prewarming is intentionally fire-and-forget. A result may arrive
    // after the owning detail page has gone away, so treat the store as a
    // disposable sink for late writes instead of calling ChangeNotifier after
    // dispose.
    if (_disposed) {
      return;
    }
    var changed = false;
    changed = _mergeInto(_blockDimensions, blockDimensions) || changed;
    changed = _mergeInto(_inlineDimensions, inlineDimensions) || changed;
    if (!changed) {
      return;
    }
    _revision += 1;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    super.dispose();
  }

  bool _mergeInto(
    Map<String, ThreadPostResourceDimension> target,
    Map<String, ThreadPostResourceDimension> source,
  ) {
    var changed = false;
    for (final entry in source.entries) {
      final existing = target[entry.key];
      if (existing != null &&
          existing.width == entry.value.width &&
          existing.height == entry.value.height) {
        continue;
      }
      target[entry.key] = entry.value;
      changed = true;
    }
    return changed;
  }
}
