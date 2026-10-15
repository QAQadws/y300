import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cache.dart';

void main() {
  test('default cache keeps sixteen chapter plans and evicts the coldest', () {
    final cache = NovelReaderPaginationCache();
    addTearDown(cache.dispose);
    final plans = [
      for (var index = 0; index < 17; index++)
        _plan('episode-$index', html: '<p>page-$index</p>'),
    ];
    for (final plan in plans.take(16)) {
      cache.put(plan);
    }
    for (final plan in plans.take(16)) {
      expect(cache.get(plan.key), same(plan));
    }
    expect(cache.get(plans.first.key), same(plans.first));
    cache.put(plans.last);

    expect(cache.length, 16);
    expect(cache.get(plans[1].key), isNull);
    expect(cache.get(plans.first.key), same(plans.first));
    for (final plan in plans.skip(2)) {
      expect(cache.get(plan.key), same(plan));
    }
  });

  test('default byte budget retains a large plan but still bounds the LRU', () {
    const mib = 1024 * 1024;
    final cache = NovelReaderPaginationCache();
    addTearDown(cache.dispose);
    final html = '<p>${'x' * (5 * mib)}</p>';
    final first = _plan('one', html: html);
    final second = _plan('two', html: html);
    cache.put(first);
    expect(cache.get(first.key), same(first));
    expect(cache.estimatedRetainedBytes, greaterThan(8 * mib));
    expect(cache.estimatedRetainedBytes, lessThanOrEqualTo(16 * mib));

    cache.put(second);
    expect(cache.length, 1);
    expect(cache.get(first.key), isNull);
    expect(cache.get(second.key), same(second));
    expect(cache.estimatedRetainedBytes, lessThanOrEqualTo(16 * mib));

    cache.put(_plan('two', html: '<p>${'x' * (9 * mib)}</p>'));
    expect(cache.get(second.key), isNull);
    expect(cache.length, 0);
    expect(cache.estimatedRetainedBytes, 0);
  });

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

  test('byte budget evicts least recent plans before the count bound', () {
    final first = _plan('one', html: '<p>one</p>');
    final second = _plan('two', html: '<p>two</p>');
    final third = _plan('six', html: '<p>six</p>');
    final probe = NovelReaderPaginationCache()
      ..put(first)
      ..put(second);
    final budget = probe.estimatedRetainedBytes;
    final cache = NovelReaderPaginationCache(
      capacity: 8,
      maxEstimatedBytes: budget,
    );
    cache
      ..put(first)
      ..put(second);
    expect(cache.get(first.key), same(first));
    cache.put(third);
    expect(cache.length, 2);
    expect(cache.get(second.key), isNull);
    expect(cache.get(first.key), same(first));
    expect(cache.get(third.key), same(third));
    expect(cache.estimatedRetainedBytes, lessThanOrEqualTo(budget));
  });

  test(
    'oversized replacement is not retained and all eviction paths clear bytes',
    () {
      final small = _plan('one', html: '<p>one</p>');
      final probe = NovelReaderPaginationCache()..put(small);
      final cache = NovelReaderPaginationCache(
        maxEstimatedBytes: probe.estimatedRetainedBytes,
      );
      cache.put(small);
      cache.put(_plan('one', html: '<p>${'long' * 200}</p>'));
      expect(cache.get(small.key), isNull);
      expect(cache.estimatedRetainedBytes, 0);
      cache
        ..put(small)
        ..evict(small.key);
      expect(cache.estimatedRetainedBytes, 0);
      cache
        ..put(small)
        ..evictEpisode('one');
      expect(cache.estimatedRetainedBytes, 0);
      cache
        ..put(small)
        ..clear();
      expect(cache.estimatedRetainedBytes, 0);
      cache.put(small);
      expect(cache.get(small.key), same(small));
    },
  );

  test('disposed plan cache ignores late writes and cannot be reopened', () {
    final plan = _plan('one', html: '<p>one</p>');
    final cache = NovelReaderPaginationCache()
      ..put(plan)
      ..dispose();
    cache
      ..clear()
      ..put(plan)
      ..dispose();
    expect(cache.isClosed, isTrue);
    expect(cache.contains(plan.key), isFalse);
    expect(cache.get(plan.key), isNull);
    expect(cache.length, 0);
    expect(cache.estimatedRetainedBytes, 0);
  });
}

NovelReaderPaginationPlan _plan(
  String episodeId, {
  int rendererRevision = 1,
  String? html,
}) {
  final anchor = NovelReaderTextAnchor(episodeId: episodeId);
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
    pages: html == null
        ? const []
        : [
            NovelReaderPageFragment(
              index: 0,
              html: html,
              startAnchor: anchor,
              endAnchor: anchor,
              imageIndices: const [],
            ),
          ],
  );
}
