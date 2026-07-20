import 'dart:collection';

import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';

/// Bounded process-local LRU cache. Pagination fragments are derived data and
/// are intentionally not written to SQLite or the downloaded content store.
final class NovelReaderPaginationCache {
  NovelReaderPaginationCache({this.capacity = 8}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final int capacity;
  final LinkedHashMap<NovelReaderPaginationKey, NovelReaderPaginationPlan>
  _entries =
      LinkedHashMap<NovelReaderPaginationKey, NovelReaderPaginationPlan>();

  int get length => _entries.length;

  bool contains(NovelReaderPaginationKey key) => _entries.containsKey(key);

  NovelReaderPaginationPlan? get(NovelReaderPaginationKey key) {
    final plan = _entries.remove(key);
    if (plan == null) {
      return null;
    }
    _entries[key] = plan;
    return plan;
  }

  void put(NovelReaderPaginationPlan plan) {
    _entries.remove(plan.key);
    _entries[plan.key] = plan;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void evict(NovelReaderPaginationKey key) {
    _entries.remove(key);
  }

  void evictEpisode(String episodeId) {
    _entries.removeWhere((key, _) => key.episodeId == episodeId);
  }

  void clear() => _entries.clear();
}
