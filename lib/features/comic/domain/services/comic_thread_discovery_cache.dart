import 'package:y300/features/comic/domain/models/comic_thread_discovery_models.dart';

/// Per-refresh cache for narrow comic discovery documents.
final class ComicThreadDiscoveryCache {
  ComicThreadDiscoveryCache();

  final Map<String, ComicThreadDiscoveryDocument> _byTid =
      <String, ComicThreadDiscoveryDocument>{};

  ComicThreadDiscoveryDocument? get(String tid) => _byTid[tid];

  void store(ComicThreadDiscoveryDocument document) {
    final tid = document.tid.trim();
    if (tid.isNotEmpty) {
      _byTid[tid] = document;
    }
  }

  bool contains(String tid) => _byTid.containsKey(tid);

  int get size => _byTid.length;
}
