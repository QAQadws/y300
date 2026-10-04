import 'dart:collection';

import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';

/// Bounded process-local LRU cache. Pagination fragments are derived data and
/// are intentionally not written to SQLite or the downloaded content store.
final class NovelReaderPaginationCache {
  NovelReaderPaginationCache({
    this.capacity = 8,
    this.maxEstimatedBytes = 8 * 1024 * 1024,
  }) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
    if (maxEstimatedBytes < 0) {
      throw ArgumentError.value(
        maxEstimatedBytes,
        'maxEstimatedBytes',
        'must be nonnegative',
      );
    }
  }

  final int capacity;
  final int maxEstimatedBytes;
  final LinkedHashMap<
    NovelReaderPaginationKey,
    ({NovelReaderPaginationPlan plan, int bytes})
  >
  _entries =
      LinkedHashMap<
        NovelReaderPaginationKey,
        ({NovelReaderPaginationPlan plan, int bytes})
      >();
  int _estimatedRetainedBytes = 0;
  bool _closed = false;

  int get length => _entries.length;
  bool get isClosed => _closed;

  /// Fixed-weight estimate of retained entries, not actual heap or in-flight memory.
  int get estimatedRetainedBytes => _estimatedRetainedBytes;

  bool contains(NovelReaderPaginationKey key) => _entries.containsKey(key);

  NovelReaderPaginationPlan? get(NovelReaderPaginationKey key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    _entries[key] = entry;
    return entry.plan;
  }

  void put(NovelReaderPaginationPlan plan) {
    if (_closed) {
      return;
    }
    evict(plan.key);
    final bytes = _estimate(plan);
    if (bytes > maxEstimatedBytes) {
      return;
    }
    _entries[plan.key] = (plan: plan, bytes: bytes);
    _estimatedRetainedBytes += bytes;
    while (_entries.length > capacity ||
        _estimatedRetainedBytes > maxEstimatedBytes) {
      evict(_entries.keys.first);
    }
  }

  void evict(NovelReaderPaginationKey key) {
    final entry = _entries.remove(key);
    if (entry != null) {
      _estimatedRetainedBytes -= entry.bytes;
    }
  }

  void evictEpisode(String episodeId) {
    final keys = _entries.keys
        .where((key) => key.episodeId == episodeId)
        .toList();
    for (final key in keys) {
      evict(key);
    }
  }

  void clear() {
    _entries.clear();
    _estimatedRetainedBytes = 0;
  }

  void dispose() {
    _closed = true;
    clear();
  }

  int _estimate(NovelReaderPaginationPlan plan) {
    var bytes =
        256 + 2 * (plan.key.cacheIdentity.length + plan.episodeId.length);
    for (final page in plan.pages) {
      bytes += 128 + 2 * page.html.length + 8 * page.imageIndices.length;
      bytes += _anchorBytes(page.startAnchor) + _anchorBytes(page.endAnchor);
      for (final range in page.anchorRanges) {
        bytes += 32 + _anchorBytes(range.start) + _anchorBytes(range.end);
      }
    }
    for (final sample in plan.measurementSamples) {
      bytes += 64 + 2 * sample.atomId.length;
    }
    return bytes;
  }

  int _anchorBytes(NovelReaderTextAnchor anchor) =>
      64 +
      2 *
          (anchor.episodeId.length +
              (anchor.nodeId?.length ?? 0) +
              (anchor.textIdentity?.length ?? 0));
}
