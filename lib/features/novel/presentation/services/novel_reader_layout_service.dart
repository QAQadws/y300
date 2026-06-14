import 'dart:collection';

import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_layout_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_layout_request.dart';

abstract interface class NovelReaderLayoutService {
  Future<NovelReaderPageLayout> resolve(NovelReaderLayoutRequest request);

  void evictEpisode(String episodeId);

  void clear();
}

class CachedNovelReaderLayoutService implements NovelReaderLayoutService {
  CachedNovelReaderLayoutService({
    NovelReaderPaginator paginator = const NovelReaderPaginator(),
    int capacity = 8,
  })  : _paginator = paginator,
        _capacity = capacity;

  final NovelReaderPaginator _paginator;
  final int _capacity;
  final LinkedHashMap<NovelReaderLayoutKey, NovelReaderPageLayout> _cache =
      LinkedHashMap<NovelReaderLayoutKey, NovelReaderPageLayout>();
  final Map<NovelReaderLayoutKey, Future<NovelReaderPageLayout>> _inFlight =
      <NovelReaderLayoutKey, Future<NovelReaderPageLayout>>{};

  @override
  Future<NovelReaderPageLayout> resolve(NovelReaderLayoutRequest request) {
    final key = request.key;
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future<NovelReaderPageLayout>.value(cached);
    }
    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }
    final future = Future<NovelReaderPageLayout>.microtask(() {
      return _paginator.paginate(
        document: request.document,
        typography: request.metrics,
        viewportSize: request.viewport,
      );
    }).then((layout) {
      _inFlight.remove(key);
      _cache[key] = layout;
      _trimToCapacity();
      return layout;
    }, onError: (Object error, StackTrace stackTrace) {
      _inFlight.remove(key);
      throw error;
    });
    _inFlight[key] = future;
    return future;
  }

  @override
  void evictEpisode(String episodeId) {
    _cache.removeWhere((key, _) => key.episodeId == episodeId);
    _inFlight.removeWhere((key, _) => key.episodeId == episodeId);
  }

  @override
  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  void _trimToCapacity() {
    while (_cache.length > _capacity) {
      _cache.remove(_cache.keys.first);
    }
  }
}
