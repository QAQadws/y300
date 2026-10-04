import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_snapshot.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';

void main() {
  test('append preserves old prefixes, iterators and indexed reads', () {
    final builder = NovelReaderPageSnapshotBuilder();
    final empty = builder.snapshot;
    final pages = List<NovelReaderPageFragment>.generate(257, _page);
    for (final page in pages.take(129)) {
      builder.add(page);
    }
    final prefix = builder.snapshot;
    final iterator = prefix.iterator;
    expect(iterator.moveNext(), isTrue);
    expect(iterator.current, same(pages.first));
    expect(builder.snapshot, same(prefix));

    for (final page in pages.skip(129)) {
      builder.add(page);
    }
    final complete = builder.snapshot;

    expect(empty, isEmpty);
    expect(prefix, hasLength(129));
    expect(complete, hasLength(257));
    expect(complete, isNot(same(prefix)));
    expect(builder.length, 257);
    for (final index in [0, 7, 63, 128]) {
      expect(prefix[index], same(pages[index]));
      expect(complete[index], same(prefix[index]));
    }
    final remaining = <NovelReaderPageFragment>[];
    while (iterator.moveNext()) {
      remaining.add(iterator.current);
    }
    expect(remaining, orderedEquals(pages.getRange(1, 129)));
    expect(prefix.first, same(pages.first));
    expect(prefix.last, same(pages[128]));
    expect(prefix.elementAt(63), same(pages[63]));
    expect(prefix.getRange(62, 65), orderedEquals(pages.getRange(62, 65)));
    expect(prefix.reversed.first, same(pages[128]));
    expect(prefix.asMap().length, 129);
    expect(prefix.asMap()[129], isNull);
    expect(prefix.cast<NovelReaderPageFragment>(), orderedEquals(prefix));
    for (final index in [-1, 129, 256]) {
      expect(() => prefix[index], throwsRangeError);
    }
    final ownedCopy = prefix.sublist(62, 65)..clear();
    expect(ownedCopy, isEmpty);
    expect(prefix[63], same(pages[63]));
  });

  test('every mutation API rejects populated and empty snapshots', () {
    final builder = NovelReaderPageSnapshotBuilder();
    final empty = builder.snapshot;
    final page = _page(0);
    builder.add(page);
    final populated = builder.snapshot;

    for (final snapshot in [empty, populated]) {
      final mutations = <String, void Function()>{
        'index': () => snapshot[0] = page,
        'length': () => snapshot.length = 0,
        'first': () => snapshot.first = page,
        'last': () => snapshot.last = page,
        'add': () => snapshot.add(page),
        'addAll': () => snapshot.addAll(const []),
        'insert': () => snapshot.insert(0, page),
        'insertAll': () => snapshot.insertAll(0, const []),
        'remove': () => snapshot.remove(page),
        'removeAt': () => snapshot.removeAt(0),
        'removeLast': () => snapshot.removeLast(),
        'removeWhere': () => snapshot.removeWhere((_) => false),
        'retainWhere': () => snapshot.retainWhere((_) => true),
        'clear': snapshot.clear,
        'sort': () => snapshot.sort((a, b) => a.index.compareTo(b.index)),
        'shuffle': snapshot.shuffle,
        'setAll': () => snapshot.setAll(0, const []),
        'setRange': () => snapshot.setRange(0, 0, const []),
        'removeRange': () => snapshot.removeRange(0, 0),
        'replaceRange': () => snapshot.replaceRange(0, 0, const []),
        'fillRange': () => snapshot.fillRange(0, 0, page),
        'cast': () => snapshot.cast<Object?>()[0] = page,
      };
      for (final mutation in mutations.entries) {
        expect(mutation.value, throwsUnsupportedError, reason: mutation.key);
      }
    }
    expect(empty, isEmpty);
    expect(populated, orderedEquals([page]));
    expect(builder.snapshot, same(populated));
  });

  test('plans reuse only the trusted frozen snapshot', () {
    final builder = NovelReaderPageSnapshotBuilder()..add(_page(0));
    final snapshot = builder.snapshot;
    final first = _plan(snapshot);
    final second = _plan(snapshot);

    expect(first.pages, same(snapshot));
    expect(second.pages, same(first.pages));
    builder.add(_page(1));
    final next = _plan(builder.snapshot);
    expect(first.pageCount, 1);
    expect(second.pages.single, same(snapshot.single));
    expect(next.pageCount, 2);
    expect(next.pages.first, same(first.pages.first));
    expect(first.pageAt(1), isNull);
  });

  test('plans copy caller lists even when a view is read-only', () {
    for (final asReadOnlyView in [false, true]) {
      final firstPage = _page(0);
      final source = <NovelReaderPageFragment>[firstPage];
      final input = asReadOnlyView
          ? UnmodifiableListView<NovelReaderPageFragment>(source)
          : source;
      final plan = _plan(input);

      source[0] = _page(1);
      source.add(_page(2));
      source.clear();

      expect(plan.pages, isNot(same(input)));
      expect(plan.pages.single, same(firstPage));
      expect(() => plan.pages.clear(), throwsUnsupportedError);
    }
  });
}

NovelReaderPageFragment _page(int index) => NovelReaderPageFragment(
  index: index,
  html: '<p>page-$index</p>',
  startAnchor: NovelReaderTextAnchor(
    episodeId: 'snapshot-test',
    nodeId: 'node-$index',
  ),
  endAnchor: NovelReaderTextAnchor(
    episodeId: 'snapshot-test',
    nodeId: 'node-$index',
    textOffset: 6,
  ),
  imageIndices: const [],
);

NovelReaderPaginationPlan _plan(List<NovelReaderPageFragment> pages) =>
    NovelReaderPaginationPlan(
      key: const NovelReaderPaginationKey(
        episodeId: 'snapshot-test',
        contentHash: 'content',
        viewportWidthPx: 320,
        viewportHeightPx: 600,
        typographySignature: 'font',
        themeSignature: 'theme',
        imageDimensionRevision: 0,
        rendererRevision: 18,
      ),
      episodeId: 'snapshot-test',
      pages: pages,
    );
