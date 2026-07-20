import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cache.dart';

void main() {
  test('keeps a bounded LRU and refreshes recency on read', () {
    final cache = NovelReaderPaginationCache(capacity: 2);
    final first = _plan('one');
    final second = _plan('two');
    final third = _plan('three');

    cache.put(first);
    cache.put(second);
    expect(cache.get(first.key), same(first));
    cache.put(third);

    expect(cache.get(first.key), same(first));
    expect(cache.get(second.key), isNull);
    expect(cache.get(third.key), same(third));
  });

  test('evicts all layouts for one episode without touching another', () {
    final cache = NovelReaderPaginationCache(capacity: 4);
    final first = _plan('episode-a');
    final second = _plan('episode-a', rendererRevision: 2);
    final other = _plan('episode-b');
    cache
      ..put(first)
      ..put(second)
      ..put(other)
      ..evictEpisode('episode-a');

    expect(cache.length, 1);
    expect(cache.get(other.key), same(other));
  });
}

NovelReaderPaginationPlan _plan(String episodeId, {int rendererRevision = 1}) {
  return NovelReaderPaginationPlan(
    key: NovelReaderPaginationKey(
      episodeId: episodeId,
      contentHash: 'content',
      viewportWidthPx: 320,
      viewportHeightPx: 600,
      typographySignature: 'typography',
      themeSignature: 'theme',
      imageDimensionRevision: 1,
      rendererRevision: rendererRevision,
    ),
    episodeId: episodeId,
    pages: const [],
  );
}
