import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _limits = ForumBodyTextPageSessionLimits(
  maxPages: 48,
  maxFragments: 128,
  maxParagraphs: 64,
  maxTextCodeUnits: 4096,
  maxRuns: 256,
  maxIssuedLeases: 16,
);

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
  fontRevision: 'table-layout',
  linkColor: const Color(0xff0000ff),
  paragraphAfter: 0,
);

ForumBodyDocument _parse(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'table-layout',
  conversionIdentity: 'none',
);

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 24,
    maxEstimatedBytes: 1 << 22,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyTablePreparation _start(
  ForumBodyDocument document,
  ForumBodyParagraphCache cache, {
  double availableWidth = 120,
  ForumBodyTextPageSessionLimits limits = _limits,
  ForumBodyImageResolver? images,
}) {
  final work = ForumBodyTablePreparation(
    document: document,
    table: document.tableElements.single,
    reader: _reader,
    cache: cache,
    layoutId: 'table-layout',
    availableWidth: availableWidth,
    limits: limits,
    imageResolver: images,
  );
  addTearDown(work.close);
  return work;
}

ForumBodyTableLayout _layout(ForumBodyTablePreparation work) {
  for (var i = 0; i < 10000 && !work.isReady; i++) {
    final step = work.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
  }
  expect(work.isReady, isTrue);
  final layout = work.takeLayout();
  addTearDown(layout.close);
  return layout;
}

List<ForumBodyPreparedTextFragment> _open(ForumBodyTableAreaLayout cell) {
  final prep = cell.openPagePreparation(0);
  try {
    for (var i = 0; i < 1000 && !prep.isReady; i++) {
      prep.advance(maxFragments: 1, maxParts: 1);
    }
    return prep.takeFragments();
  } finally {
    prep.close();
  }
}

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource();
  @override
  String get cacheKey => 'table-cell-image';
}

ForumBodyTextPageSession _book(
  ForumBodyDocument document,
  ForumBodyParagraphCache cache, {
  String layoutId = 'table-book',
  ForumBodyTextPageSessionLimits limits = _limits,
  ForumBodyTableExtent extent = ForumBodyTableExtent.bookPage,
  bool captureFloats = false,
}) {
  final session = ForumBodyTextPageSession(
    document: document,
    reader: _reader,
    cache: cache,
    limits: limits,
    layoutId: layoutId,
    width: 100,
    height: 45,
    dedicatedTables: true,
    tableExtent: extent,
    captureFloats: captureFloats,
  );
  addTearDown(session.close);
  return session;
}

void _advanceBook(ForumBodyTextPageSession session, int pageCount) {
  for (var i = 0; i < 2000 && session.snapshot.length < pageCount; i++) {
    final step = session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.pagesPublished, lessThanOrEqualTo(1));
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
  }
  expect(session.snapshot, hasLength(pageCount));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cached table cells become visible without a frame per cell', (
    tester,
  ) async {
    final cache = _cache();
    final html =
        '<table cellpadding="0">${List.generate(4, (row) => '<tr><td>cell${row * 2}</td><td>cell${row * 2 + 1}</td></tr>').join()}</table>';
    final layout = _layout(_start(_parse(html), cache));
    expect(layout.cells, hasLength(8));
    for (final cell in layout.cells) {
      for (final fragment in _open(cell)) {
        fragment.close();
      }
    }
    final builds = cache.layoutBuildCount;
    final horizontal = ScrollController(), vertical = ScrollController();
    addTearDown(horizontal.dispose);
    addTearDown(vertical.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    var ready = false;
    final cells = <ForumBodyTableAreaLayout>{};
    final errors = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          child: SizedBox(
            width: 120,
            height: 100,
            child: ForumBodyTableBookViewport(
              layout: layout,
              horizontalController: horizontal,
              verticalController: vertical,
              onFailure: (error, _) => errors.add(error),
              onReadyChanged: (value) => ready = value,
              buildSlice: (_, area, page, fragments) {
                cells.add(area);
                return ForumBodyTextPageSurface.prepared(
                  snapshot: area.snapshot,
                  pageIndex: page,
                  layoutId: area.snapshot.layoutId,
                  fragments: fragments,
                  compactHeight: true,
                );
              },
            ),
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 6 && !ready; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ready, true);
    expect(cells, hasLength(8));
    expect(cache.layoutBuildCount, builds);
    expect(errors, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(cache.activeLeases, 0);
    expect(tester.takeException(), isNull);
  });

  test('a whole native table publishes as one ordered book page', () {
    final document = _parse(
      '<p>before</p><table width="190" height="100"><caption>cap</caption>'
      '<tr><td rowspan="2"><ruby>A<rt>aa</rt></ruby></td><td>top</td></tr>'
      '<tr><td>bottom</td></tr></table><p>after</p>',
    );
    final cache = _cache();
    final session = _book(document, cache);
    _advanceBook(session, 1);
    final prefix = session.snapshot;
    expect(prefix.single.table, isNull);
    expect(prefix.single.fragments.single.paragraphIndex, 0);

    _advanceBook(session, 2);
    final page = session.snapshot[1];
    final layout = session.tableLayoutForPage(1)!;
    expect(prefix, hasLength(1));
    expect(page.table!.path, document.tableElements.single.path);
    expect(page.table!.bounds, const Rect.fromLTWH(0, 0, 100, 45));
    expect(page.table!.contentSize.width, 190);
    expect(page.table!.contentSize.height, greaterThan(100));
    expect(page.fragments, isEmpty);
    expect(layout.cells, hasLength(3));
    expect(layout.geometry.grid.cells.first.rowSpan, 2);
    final ruby = _open(layout.cells.first).single;
    expect(ruby.projection.text, 'Aaa');
    ruby.close();

    _advanceBook(session, 3);
    expect(session.isComplete, isTrue);
    expect(session.snapshot.last.fragments.single.paragraphIndex, 1);
    expect(session.retainedParagraphCount, 6);
    expect(cache.activeLeases, 0);

    final retry = _book(document, cache, layoutId: 'retry');
    _advanceBook(retry, 3);
    expect(retry.snapshot[1].table, page.table);
    session.close();
    expect(layout.isClosed, isTrue);
    expect(() => session.tableLayoutForPage(1), throwsStateError);
  });

  test('a directly floated table keeps its dedicated book page and source', () {
    final document = _parse(
      'Before<table style="float:right;margin-left:5px" width="190">'
      '<tr><td colspan="2">head</td></tr><tr><td>A</td><td>B</td></tr>'
      '</table>After',
    );
    final session = _book(document, _cache(), captureFloats: true);
    _advanceBook(session, 1);
    final prefix = session.snapshot;
    _advanceBook(session, 3);
    final pages = session.snapshot;
    final table = document.tableElements.single;
    expect(pages.first, same(prefix.single));
    expect(pages[1].table!.path, table.path);
    expect(pages[1].table!.sourceRange, (
      runeStart: table.source.runeStart,
      runeEnd: table.source.runeEnd,
    ));
    expect(pages[1].table!.bounds, const Rect.fromLTWH(0, 0, 100, 45));
    expect(pages[1].table!.contentSize.width, 190);
    expect(pages[1].fragments, isEmpty);
    final lease = session.acquireTablePage(1)!;
    expect(lease.layout.geometry.grid.cells.first.columnSpan, 2);
    for (final (index, expected) in [(0, 'Before'), (2, 'After')]) {
      final delivery = session.preparePageFragments(index).single;
      expect(delivery.projection.text, expected);
      delivery.close();
    }
    session.close();
    expect(lease.isActive, isFalse);
    expect(lease.layout.isClosed, isTrue);
  });

  test('flowing table slices keep their measured height and source order', () {
    final document = _parse(
      '<p style="margin-bottom:11px">before</p>'
      '<div style="background-color:#ddeeff"><table width="190" height="240">'
      '<caption>cap</caption><tr><td>cell</td></tr></table></div><p>after</p>',
    );
    final cache = _cache();
    final session = _book(
      document,
      cache,
      extent: ForumBodyTableExtent.natural,
    );
    _advanceBook(session, 3);
    final pages = session.snapshot;
    final tablePage = pages[1];
    final table = tablePage.table!;
    final layout = session.tableLayoutForPage(1)!;
    expect(table.bounds.top, 0);
    expect(table.bounds.height, layout.size.height);
    expect(table.bounds.height, greaterThan(240));
    expect(tablePage.usedHeight, table.bounds.bottom);
    expect(tablePage.backgrounds.single.height, layout.size.height);
    expect(tablePage.fragments, isEmpty);
    expect(pages.first.fragments.single.paragraphIndex, 0);
    final before = pages.first.fragments.single;
    expect(pages.first.usedHeight - before.top - before.height, 11);
    expect(pages.last.fragments.single.paragraphIndex, 1);
    expect(session.isComplete, isTrue);
    expect(cache.activeLeases, 0);
  });

  test(
    'a tall floated table wraps text past the nominal flow slice height',
    () {
      final document = _parse(
        'AB<table style="float:right;margin-left:5px" width="35" height="72">'
        '<tr><td>字</td></tr></table> ${'aa ' * 24}END',
      );
      final session = _book(
        document,
        _cache(),
        extent: ForumBodyTableExtent.natural,
        captureFloats: true,
      );
      _advanceBook(session, 2);
      final page = session.snapshot.first;
      final frame = page.floatedTables.single;
      final source = document.tableElements.single;
      expect(frame.path, source.path);
      expect(page.table, isNull);
      expect(frame.bounds, const Rect.fromLTWH(65, 0, 35, 72));
      final fragment = page.fragments.single;
      expect(fragment.width, 60);
      expect(fragment.top, 0);
      expect(fragment.height, greaterThan(session.snapshot.height));
      expect(fragment.height, greaterThanOrEqualTo(frame.bounds.bottom));
      final layout = session.tableLayoutForPage(0, path: frame.path)!;
      final cell = _open(layout.cells.single).single;
      expect(cell.projection.text, '字');
      cell.close();
      expect(session.snapshot.last.floatedTables, isEmpty);
      expect(session.snapshot.last.fragments.single.width, 100);
      session.close();
      expect(layout.isClosed, isTrue);
    },
  );

  test('a mixed book float keeps the text on both sides of its table', () {
    final document = _parse(
      '<span style="float:right">Before <b>bold</b>'
      '<div><table><tr><td>cell</td></tr></table></div>'
      'After <i>italic</i></span>',
    );
    final session = _book(document, _cache(), captureFloats: true);
    _advanceBook(session, 3);
    expect(session.snapshot[1].table?.path, document.tableElements.single.path);
    for (final (index, text) in [(0, 'Before bold'), (2, 'After italic')]) {
      final delivery = session.preparePageFragments(index).single;
      expect(delivery.projection.text, text);
      delivery.close();
    }
  });

  test('a failure discards an unpublished floated table and its budget', () {
    final cache = _cache();
    final session = _book(
      _parse(
        '<p>before</p><table style="float:right" width="30" height="60">'
        '<tr><td>cell</td></tr></table><div style="position:absolute">X</div>',
      ),
      cache,
      extent: ForumBodyTableExtent.natural,
      captureFloats: true,
    );
    _advanceBook(session, 1);
    final prefix = session.snapshot;
    final text = session.retainedTextCodeUnits;
    final runs = session.retainedRuns;
    expect(
      () => _advanceBook(session, 2),
      throwsA(
        isA<ForumBodyBlockFlowException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyBlockFlowFailure.geometry,
        ),
      ),
    );
    expect(session.snapshot, same(prefix));
    expect(session.retainedParagraphCount, 1);
    expect(session.retainedTextCodeUnits, text);
    expect(session.retainedRuns, runs);
    expect(session.activeIssuedTablePages, 0);
    expect(cache.activeLeases, 0);
  });

  testWidgets('a wrapped float shares its slice and keeps table scroll state', (
    tester,
  ) async {
    final cache = _cache();
    final document = _parse(
      '<span style="float:left;width:54px;margin-right:4px">'
      '<div><table width="150" cellspacing="0" cellpadding="0">'
      '<tr height="25"><td width="70">left</td><td>right</td></tr>'
      '</table></div></span>${'aa ' * 15}END',
    );
    final session = _book(
      document,
      cache,
      extent: ForumBodyTableExtent.natural,
      captureFloats: true,
    );
    _advanceBook(session, 2);
    final page = session.snapshot.first;
    final frame = page.floatedTables.single;
    expect(frame.bounds, const Rect.fromLTWH(0, 0, 54, 25));
    expect(frame.contentSize.width, 150);
    expect(page.fragments.first.left, 58);
    expect(page.fragments.first.width, 42);
    final outer = ScrollController();
    addTearDown(outer.dispose);
    final errors = <Object>[];
    final windows = <ForumBodyTableVisibleWindow>[];
    final app = MaterialApp(
      home: Align(
        child: SizedBox(
          width: 100,
          height: 40,
          child: CustomScrollView(
            controller: outer,
            slivers: [
              ForumBodyFlowSliver(
                session: session,
                prefix: session.snapshot,
                onFailure: (error, _) => errors.add(error),
                onFloatedTableWindowChanged: (slice, actual, window) {
                  expect(slice, 0);
                  expect(actual, frame);
                  if (window != null) windows.add(window);
                },
                buildSlice: (context, snapshot, index, fragments) =>
                    ForumBodyTextPageSurface.prepared(
                      snapshot: snapshot,
                      pageIndex: index,
                      layoutId: snapshot.layoutId,
                      fragments: fragments,
                      compactHeight: true,
                    ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    final finder = find.byType(ForumBodyTableFlowViewport);
    final viewport = tester.widget<ForumBodyTableFlowViewport>(finder);
    expect(tester.getSize(finder), frame.bounds.size);
    expect(viewport.horizontalController.position.maxScrollExtent, 96);
    expect(session.activeIssuedTablePages, 1);
    final boundary = tester.renderObject<RenderForumBodyFlowBoundary>(
      find.byType(ForumBodyFlowSliver),
    );
    expect(boundary.borrowTextWindow()!.slices.first.index, 0);
    viewport.horizontalController.jumpTo(96);
    await tester.pumpAndSettle();
    expect(windows.last.bounds.left, 96);
    expect(
      windows.last.slices.single.area.element.path,
      viewport.layout.cells.last.element.path,
    );
    outer.jumpTo(outer.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(finder, findsNothing);
    expect(session.activeIssuedTablePages, 0);
    expect(windows.last.isCurrent, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(session.flowTableOffset(0, frame.path), 96);
    await tester.pumpWidget(app);
    outer.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ForumBodyTableFlowViewport>(finder)
          .horizontalController
          .offset,
      96,
    );
    expect(errors, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(session.activeIssuedTablePages, 0);
    expect(session.activeIssuedFragments, 0);
    expect(cache.activeLeases, 0);
  });

  test('positive paragraph gaps survive flowing slice boundaries', () {
    final session = _book(
      _parse(
        '<p style="margin-bottom:58px">before</p>'
        '<p style="background-color:#ddeeff">after</p>',
      ),
      _cache(),
      extent: ForumBodyTableExtent.natural,
    );
    _advanceBook(session, 2);
    final pages = session.snapshot;
    final before = pages.first.fragments.single;
    final after = pages.last.fragments.single;
    expect(pages.first.usedHeight + after.top - before.top - before.height, 58);
    expect(pages.first.backgrounds, isEmpty);
    expect(pages.last.backgrounds.single.top, after.top);
  });

  test('table content counts towards the chapter budget across pages', () {
    final cache = _cache();
    final session = _book(
      _parse(
        '<p>start</p><table><tr><td>one</td></tr></table>'
        '<table><tr><td>two</td></tr></table>',
      ),
      cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 3,
        maxFragments: 128,
        maxParagraphs: 2,
        maxTextCodeUnits: 4096,
        maxRuns: 256,
        maxIssuedLeases: 16,
      ),
    );
    _advanceBook(session, 2);
    final prefix = session.snapshot;
    final layout = session.tableLayoutForPage(1)!;
    expect(
      () {
        for (var i = 0; i < 2000 && !session.isComplete; i++) {
          session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
        }
      },
      throwsA(
        isA<ForumBodyTextPageSessionException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyTextPageSessionFailure.paragraphLimit,
        ),
      ),
    );
    expect(session.snapshot, same(prefix));
    expect(session.state, ForumBodyTextPageSessionState.failed);
    expect(session.tableLayoutForPage(1), same(layout));
    final fragment = _open(layout.cells.single).single;
    expect(fragment.projection.text, 'one');
    fragment.close();
    expect(cache.activeLeases, 0);
  });

  testWidgets('a measured table body paints at its occupied height', (
    tester,
  ) async {
    final document = _parse(
      '<table><tr><td><a href="/thread">link</a></td></tr></table>',
    );
    final cache = _cache();
    final layout = _layout(_start(document, cache));
    final cell = layout.cells.single;
    final snapshot = cell.snapshot;
    final fragments = _open(cell);
    final point = fragments.single.glyphBoxes(0, 1).single.toRect().center;
    final hits = <int>[];
    const key = ValueKey('measured-cell');
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          child: SizedBox.fromSize(
            size: cell.contentBounds.size,
            child: ForumBodyTextPageSurface.prepared(
              key: key,
              snapshot: snapshot,
              pageIndex: 0,
              layoutId: snapshot.layoutId,
              fragments: fragments,
              compactHeight: true,
              onSourceTap: (_, position) {
                if (position.isExact) hits.add(position.sourceRune);
              },
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(key)), cell.contentBounds.size);
    await tester.tapAt(tester.getTopLeft(find.byKey(key)) + point);
    expect(hits, hasLength(1));
    expect(
      hits.single,
      inInclusiveRange(
        cell.element.source.runeStart,
        cell.element.source.runeEnd,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(cache.activeLeases, 0);
  });

  testWidgets('book viewport keeps edge drags and releases offscreen slices', (
    tester,
  ) async {
    final cache = _cache();
    final session = _book(
      _parse(
        '<span style="float:left;margin-right:5px"> \n <div>'
        '<table width="180" cellpadding="2"><tr height="120">'
        '<td rowspan="2" width="100"><ruby>A<rt>aa</rt></ruby></td>'
        '<td>right</td></tr><tr><td>tail</td></tr></table></div></span>',
      ),
      cache,
      captureFloats: true,
    );
    _advanceBook(session, 1);
    final layout = session.tableLayoutForPage(0)!;
    final h = ScrollController();
    final v = ScrollController();
    final outer = PageController();
    addTearDown(h.dispose);
    addTearDown(v.dispose);
    addTearDown(outer.dispose);
    final mounted = <ForumBodyTableAreaLayout, ForumBodyPreparedTextFragment>{};
    final ready = <bool>[];
    final windows = <ForumBodyTableVisibleWindow?>[];
    final errors = <Object>[];
    const tableKey = ValueKey('table-book-viewport');
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          child: SizedBox(
            width: 80,
            height: 48,
            child: PageView(
              controller: outer,
              children: [
                ForumBodyTableBookViewport(
                  key: tableKey,
                  layout: layout,
                  horizontalController: h,
                  verticalController: v,
                  onReadyChanged: ready.add,
                  onWindowChanged: windows.add,
                  onFailure: (error, _) => errors.add(error),
                  buildSlice: (context, area, index, fragments) {
                    mounted[area] = fragments.single;
                    return ForumBodyTextPageSurface.prepared(
                      snapshot: area.snapshot,
                      pageIndex: index,
                      layoutId: area.snapshot.layoutId,
                      fragments: fragments,
                      compactHeight: true,
                    );
                  },
                ),
                const Text('next'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = mounted[layout.cells.first]!;
    expect(first.projection.text, 'Aaa');
    expect(first.isActive, isTrue);
    expect(mounted, hasLength(1));
    expect(ready, [true]);
    final origin = windows.single!;
    expect(origin.isCurrent, isTrue);
    expect(origin.bounds, const Rect.fromLTWH(0, 0, 80, 48));
    expect(origin.slices.single.area, same(layout.cells.first));
    expect(origin.slices.single.fragments.single, same(first));
    expect(origin.hasUserScrolled, isFalse);

    h.jumpTo(h.position.maxScrollExtent);
    v.jumpTo(v.position.maxScrollExtent);
    expect(origin.isCurrent, isFalse);
    await tester.pumpAndSettle();
    expect(first.isActive, isFalse);
    expect(mounted[layout.cells.last]!.projection.text, 'tail');
    expect(ready, [true, false, true]);
    expect(errors, isEmpty);
    expect(windows.last!.slices.single.area, same(layout.cells.last));
    expect(windows.last!.hasUserScrolled, isFalse);

    await tester.drag(find.byKey(tableKey), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(h.offset, h.position.maxScrollExtent);
    expect(outer.page, 0);
    expect(windows.last!.hasUserScrolled, isFalse);
    await tester.drag(find.byKey(tableKey), const Offset(0, 160));
    await tester.pumpAndSettle();
    final scrolled = windows.last!;
    expect(scrolled.hasUserScrolled, isTrue);
    expect(scrolled.bounds.top, 0);
    expect(
      scrolled.slices.map((slice) => slice.area),
      contains(layout.cells[1]),
    );
    expect(
      scrolled.slices.every((slice) => slice.bounds.overlaps(scrolled.bounds)),
      isTrue,
    );
    outer.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(find.text('next'), findsOneWidget);
    expect(cache.activeLeases, 0);
    expect(scrolled.isCurrent, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'flowing table follows outer vertical clip through scroll and reflow',
    (tester) async {
      final cache = _cache();
      final layout = _layout(
        _start(
          _parse(
            '<table width="240" cellspacing="0" cellpadding="0"><tr height="240">'
            '<td width="140"><ruby>A<rt>aa</rt></ruby></td><td width="100">right</td></tr>'
            '<tr><td colspan="2">tail</td></tr></table>',
          ),
          cache,
          availableWidth: 100,
        ),
      );
      final horizontal = ScrollController();
      final outer = ScrollController();
      final prefix = ValueNotifier(0.0);
      addTearDown(horizontal.dispose);
      addTearDown(outer.dispose);
      addTearDown(prefix.dispose);
      final windows = <ForumBodyTableVisibleWindow?>[];
      final errors = <Object>[];
      final table = ForumBodyTableFlowViewport(
        layout: layout,
        horizontalController: horizontal,
        onFailure: (error, _) => errors.add(error),
        onWindowChanged: windows.add,
        buildSlice: (context, area, page, fragments) =>
            ForumBodyTextPageSurface.prepared(
              snapshot: area.snapshot,
              pageIndex: page,
              layoutId: area.snapshot.layoutId,
              fragments: fragments,
              compactHeight: true,
            ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            child: SizedBox(
              width: 100,
              height: 70,
              child: SingleChildScrollView(
                controller: outer,
                child: ValueListenableBuilder(
                  valueListenable: prefix,
                  child: RepaintBoundary(child: table),
                  builder: (context, height, child) => Column(
                    children: [
                      SizedBox(height: height),
                      child!,
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byWidget(table)),
        Size(100, layout.size.height),
      );
      expect(find.byType(Scrollable), findsNWidgets(2));
      expect(horizontal.position.maxScrollExtent, 140);
      final origin = windows.last!;
      expect(origin.bounds, const Rect.fromLTWH(0, 0, 100, 70));
      expect(origin.slices.single.area, same(layout.cells.first));
      final ruby = origin.slices.single.fragments.single;
      expect(ruby.projection.text, 'Aaa');

      await tester.dragFrom(
        tester.getCenter(find.byWidget(table)) -
            Offset(0, layout.size.height / 2 - 35),
        const Offset(-170, 0),
      );
      await tester.pumpAndSettle();
      expect(outer.offset, 0);
      expect(horizontal.offset, horizontal.position.maxScrollExtent);
      expect(origin.isCurrent, isFalse);
      expect(ruby.isActive, isFalse);
      expect(windows.last!.slices.single.area, same(layout.cells[1]));
      expect(windows.last!.hasUserScrolled, isTrue);

      outer.jumpTo(layout.size.height - 40);
      await tester.pumpAndSettle();
      expect(windows.last!.slices.single.area, same(layout.cells.last));
      expect(windows.last!.hasUserScrolled, isFalse);
      final y = outer.offset;
      await tester.dragFrom(const Offset(400, 300), const Offset(0, 45));
      await tester.pumpAndSettle();
      expect(outer.offset, lessThan(y));
      expect(horizontal.offset, 140);

      outer.jumpTo(0);
      horizontal.jumpTo(0);
      await tester.pumpAndSettle();
      final retained = windows.last!;
      prefix.value = 150;
      await tester.pumpAndSettle();
      expect(outer.offset, 0);
      expect(retained.isCurrent, isFalse);
      expect(windows.last, isNull);
      expect(cache.activeLeases, 0);
      prefix.value = 0;
      await tester.pumpAndSettle();
      expect(windows.last!.slices.single.area, same(layout.cells.first));
      expect(errors, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(cache.activeLeases, 0);
    },
  );

  testWidgets('a flowing table that fits creates no inner scrollable', (
    tester,
  ) async {
    final layout = _layout(
      _start(
        _parse('<table width="55"><tr height="120"><td>fits</td></tr></table>'),
        _cache(),
        availableWidth: 100,
      ),
    );
    final horizontal = ScrollController();
    addTearDown(horizontal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          child: SizedBox(
            width: 100,
            height: 45,
            child: SingleChildScrollView(
              child: ForumBodyTableFlowViewport(
                layout: layout,
                horizontalController: horizontal,
                onFailure: (error, _) => fail(error.toString()),
                buildSlice: (context, area, page, fragments) =>
                    ForumBodyTextPageSurface.prepared(
                      snapshot: area.snapshot,
                      pageIndex: page,
                      layoutId: area.snapshot.layoutId,
                      fragments: fragments,
                      compactHeight: true,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Scrollable), findsOneWidget);
    expect(horizontal.hasClients, isFalse);
    expect(find.byType(ForumBodyTextPageSurface), findsOneWidget);
  });

  testWidgets('native flowing sliver materializes its exact measured prefix', (
    tester,
  ) async {
    final cache = _cache();
    final session = _book(
      _parse(
        '<p>before</p><table width="240" cellspacing="0" cellpadding="0">'
        '<tr height="240"><td width="140">left</td><td width="100">right</td></tr>'
        '<tr><td colspan="2">tail</td></tr></table><p>after</p>',
      ),
      cache,
      extent: ForumBodyTableExtent.natural,
    );
    _advanceBook(session, 1);
    final prefix = ValueNotifier(session.snapshot);
    final width = ValueNotifier(100.0);
    final outer = ScrollController();
    addTearDown(prefix.dispose);
    addTearDown(width.dispose);
    addTearDown(outer.dispose);
    final errors = <Object>[];
    final readiness = <bool>[];
    const viewportHeight = 55.0;
    const trailingHeight = 120.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          child: ValueListenableBuilder(
            valueListenable: width,
            builder: (context, value, child) =>
                SizedBox(width: value, height: viewportHeight, child: child),
            child: CustomScrollView(
              controller: outer,
              slivers: [
                ValueListenableBuilder(
                  valueListenable: prefix,
                  builder: (context, value, _) => ForumBodyFlowSliver(
                    session: session,
                    prefix: value,
                    initialTableOffset: (slice: 1, offset: 20),
                    onFailure: (error, _) => errors.add(error),
                    onReadyChanged: readiness.add,
                    buildSlice: (context, snapshot, index, fragments) =>
                        ForumBodyTextPageSurface.prepared(
                          snapshot: snapshot,
                          pageIndex: index,
                          layoutId: snapshot.layoutId,
                          fragments: fragments,
                          compactHeight: true,
                        ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: trailingHeight),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(readiness, [true]);
    final boundary = tester.renderObject<RenderForumBodyFlowBoundary>(
      find.byType(ForumBodyFlowSliver),
    );
    expect(boundary.finalBoundaryKnown, isFalse);
    final firstWindow = boundary.borrowTextWindow()!;
    expect(firstWindow.slices.single.index, 0);
    expect(firstWindow.slices.single.top, 0);
    expect(firstWindow.slices.single.fragments.single.isActive, isTrue);
    expect(session.activeIssuedFragments, 1);
    final table = find.byType(ForumBodyTableFlowViewport);
    expect(table, findsNothing);
    final originalExtent = outer.position.maxScrollExtent;

    _advanceBook(session, 3);
    prefix.value = session.snapshot;
    await tester.pumpAndSettle();
    expect(boundary.finalBoundaryKnown, isTrue);
    final height = prefix.value.fold<double>(
      0,
      (sum, page) => sum + page.usedHeight,
    );
    expect(
      outer.position.maxScrollExtent,
      height + trailingHeight - viewportHeight,
    );
    expect(outer.position.maxScrollExtent, greaterThan(originalExtent + 240));
    expect(table, findsOneWidget);
    expect(session.activeIssuedTablePages, 1);
    expect(readiness.last, isTrue);
    final current = tester.widget<ForumBodyTableFlowViewport>(table);
    expect(current.horizontalController.offset, 20);
    current.horizontalController.jumpTo(80);
    await tester.pumpAndSettle();

    outer.jumpTo(prefix.value.first.usedHeight + 20);
    await tester.pumpAndSettle();
    expect(boundary.borrowTextWindow(), isNull);
    expect(firstWindow.isCurrent, isFalse);

    outer.jumpTo(height - prefix.value.last.usedHeight);
    await tester.pumpAndSettle();
    expect(table, findsNothing);
    expect(session.activeIssuedTablePages, 0);
    expect(session.activeIssuedFragments, 1);
    final lastWindow = boundary.borrowTextWindow()!;
    expect(lastWindow.slices.single.index, 2);
    expect(lastWindow.slices.single.top, height - prefix.value.last.usedHeight);
    expect(
      outer.position.maxScrollExtent,
      height + trailingHeight - viewportHeight,
    );
    outer.jumpTo(0);
    await tester.pumpAndSettle();
    final returned = tester.widget<ForumBodyTableFlowViewport>(table);
    expect(returned.horizontalController.offset, 80);
    expect(readiness.last, isTrue);
    width.value = 90;
    await tester.pumpAndSettle();
    expect(readiness.last, isFalse);
    expect(boundary.finalBoundaryKnown, isFalse);
    expect(tester.getSize(table).width, 100);
    width.value = 100;
    await tester.pumpAndSettle();
    expect(readiness.last, isTrue);
    expect(boundary.finalBoundaryKnown, isTrue);
    expect(returned.horizontalController.offset, 80);
    expect(errors, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(session.activeIssuedTablePages, 0);
    expect(session.activeIssuedFragments, 0);
    expect(cache.activeLeases, 0);
  });

  for (final reverse in [false, true]) {
    testWidgets(
      'flowing box clips to a lazy list in either growth direction ($reverse)',
      (tester) async {
        final cache = _cache();
        final session = _book(
          _parse(
            '<p>before</p><table width="240" cellspacing="0" cellpadding="0">'
            '<tr height="240"><td width="140">left</td><td width="100">right</td></tr>'
            '</table><p>after</p>',
          ),
          cache,
          extent: ForumBodyTableExtent.natural,
        );
        _advanceBook(session, 1);
        final prefix = ValueNotifier(session.snapshot);
        addTearDown(prefix.dispose);
        final outer = ScrollController();
        final errors = <Object>[];
        addTearDown(outer.dispose);
        const center = ValueKey('center');
        const surroundingHeight = 120.0;
        final leadingHeight = ValueNotifier(surroundingHeight);
        addTearDown(leadingHeight.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              child: SizedBox(
                width: 100,
                height: 55,
                child: CustomScrollView(
                  controller: outer,
                  center: reverse ? center : null,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
                  slivers: [
                    SliverList.list(
                      children: [
                        ValueListenableBuilder(
                          valueListenable: leadingHeight,
                          builder: (_, value, _) => SizedBox(height: value),
                        ),
                        ValueListenableBuilder(
                          valueListenable: prefix,
                          builder: (context, value, _) => ForumBodyFlowBox(
                            session: session,
                            prefix: value,
                            onFailure: (error, _) => errors.add(error),
                            buildSlice: (context, snapshot, index, fragments) =>
                                ForumBodyTextPageSurface.prepared(
                                  snapshot: snapshot,
                                  pageIndex: index,
                                  layoutId: snapshot.layoutId,
                                  fragments: fragments,
                                  compactHeight: true,
                                ),
                          ),
                        ),
                        const SizedBox(height: surroundingHeight),
                      ],
                    ),
                    if (reverse)
                      const SliverToBoxAdapter(
                        key: center,
                        child: SizedBox(height: 55),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final body = find.byType(ForumBodyFlowBox, skipOffstage: false);
        final table = find.byType(
          ForumBodyTableFlowViewport,
          skipOffstage: false,
        );
        expect(tester.getSize(body).height, prefix.value.single.usedHeight);
        _advanceBook(session, 3);
        prefix.value = session.snapshot;
        await tester.pumpAndSettle();
        final height = prefix.value.fold<double>(
          0,
          (total, slice) => total + slice.usedHeight,
        );
        expect(tester.getSize(body).height, height);
        expect(session.activeIssuedFragments, 0);
        expect(session.activeIssuedTablePages, 0);
        outer.jumpTo((surroundingHeight + height / 2) * (reverse ? -1 : 1));
        await tester.pumpAndSettle();
        expect(table, findsOneWidget);
        expect(session.activeIssuedTablePages, 1);
        final tableViewport = tester.widget<ForumBodyTableFlowViewport>(table);
        expect(tableViewport.verticalController, isNull);
        final outerOffset = outer.offset;
        tableViewport.horizontalController.jumpTo(55);
        await tester.pumpAndSettle();
        expect(outer.offset, outerOffset);
        expect(tableViewport.horizontalController.offset, 55);

        leadingHeight.value += height + 55;
        await tester.pumpAndSettle();
        expect(outer.offset, outerOffset);
        expect(table, findsNothing);
        expect(body, findsOneWidget);
        expect(session.activeIssuedTablePages, 0);
        expect(session.activeIssuedFragments, 0);
        leadingHeight.value = surroundingHeight;
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ForumBodyTableFlowViewport>(table)
              .horizontalController
              .offset,
          55,
        );
        expect(errors, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(session.activeIssuedFragments, 0);
        expect(session.activeIssuedTablePages, 0);
        expect(cache.activeLeases, 0);
      },
    );
  }

  test('real width probes feed columns and wrapping feeds height', () {
    final document = _parse(
      '<table cellspacing="0" cellpadding="3" style="max-width:300px">'
      '<tr><td>aaaa bb</td><td>cccc dd</td></tr></table>',
    );
    final cache = _cache();
    for (final (available, used) in [
      (120.0, 120.0),
      (80.0, 92.0),
      (500.0, 152.0),
    ]) {
      final layout = _layout(
        _start(document, cache, availableWidth: available),
      );
      expect(layout.size.width, closeTo(used, 0.001));
      expect(layout.size.height, closeTo(available > 120 ? 16 : 26, 0.001));
      expect(cache.activeLeases, 0);
      for (final area in layout.cells) {
        final delivery = _open(area);
        expect(delivery.single.lines.length, available > 120 ? 1 : 2);
        expect(area.snapshot.identity, document.identity);
        expect(area.snapshot.width, closeTo(used / 2 - 6, 0.001));
        for (final fragment in delivery) {
          fragment.close();
        }
      }
      expect(cache.activeLeases, 0);
      layout.close();
    }
  });

  test(
    'merged grid combines actual Ruby, frozen image, captions and row geometry',
    () {
      final document = _parse(
        '<table width="168" cellpadding="2" bgcolor="#f5f5f5" dir="rtl" '
        'style="border-spacing:3px 4px">'
        '<caption style="caption-side:bottom">cap</caption>'
        '<colgroup><col width="64"><col width="48"><col width="40"></colgroup>'
        '<tr bgcolor="#abc" height="32">'
        '<td rowspan="2"><ruby>A<rt>aa</rt></ruby>'
        '<img width="32" height="16" src="https://example.invalid/one.png"></td>'
        '<td colspan="2"><a href="/thread">link</a></td></tr>'
        '<tr><td>text</td><td>tail</td></tr></table>',
      );
      final cache = _cache();
      final requests = <ForumBodyElement>[];
      final layout = _layout(
        _start(
          document,
          cache,
          images: (identity, image) {
            requests.add(image);
            final raw = image.resource!.rawSource!;
            return ForumBodyImageInput(
              identity: identity,
              element: image,
              entry: ForumHtmlReadableImageEntry(
                index: 0,
                url: raw,
                rawSrc: raw,
                resource: const _Resource(),
              ),
              layout: const ForumHtmlImageLayout(aspectRatio: 2),
            );
          },
        ),
      );
      final first = layout.cells.first;
      expect(requests, [same(document.imageElements.single)]);
      expect(layout.size.width, 168);
      expect(layout.gridTop, 0);
      expect(layout.captions.single.bounds.top, layout.geometry.size.height);
      expect(layout.captions.single.bounds.bottom, layout.size.height);
      expect(layout.rowBackgrounds, [const Color(0xffaabbcc), null]);
      expect(
        layout.geometry.rowBounds(1).top - layout.geometry.rowBounds(0).bottom,
        4,
      );
      expect(first.bounds.right, 168);
      expect(first.bounds.height, layout.geometry.size.height);
      expect(first.element, same(document.nodeAtPath(first.element.path)));
      expect(first.contentBounds.left, first.bounds.left + 2);
      expect(
        first.snapshot.single.fragments.last.imageFrame!.imageRect.size,
        const Size(32, 16),
      );
      expect(cache.activeLeases, 0);

      final delivery = _open(first);
      expect(delivery.first, isA<ForumBodyPreparedInlineFragment>());
      expect(delivery.first.projection.text, 'Aaa');
      expect(
        (delivery.last as ForumBodyPreparedImageFragment).content.input.element,
        same(requests.single),
      );
      expect(cache.activeLeases, greaterThan(0));
      layout.close();
      expect(delivery.every((fragment) => !fragment.isActive), isTrue);
      expect(cache.activeLeases, 0);
    },
  );

  test('cancel and aggregate exhaustion retire child sessions and leases', () {
    final document = _parse(
      '<table><tr><td>first</td><td>second</td></tr></table>',
    );
    final cache = _cache();
    final pending = _start(document, cache);
    for (var i = 0; i < 300 && cache.layoutBuildCount == 0; i++) {
      pending.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    }
    expect(cache.layoutBuildCount, greaterThan(0));
    pending.close();
    expect(cache.activeLeases, 0);
    expect(pending.takeLayout, throwsStateError);

    final tooSmall = _start(
      document,
      cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 8,
        maxFragments: 8,
        maxParagraphs: 1,
        maxTextCodeUnits: 1024,
        maxRuns: 128,
        maxIssuedLeases: 16,
      ),
    );
    expect(
      () => _layout(tooSmall),
      throwsA(
        isA<ForumBodyTableException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyTableFailure.workLimit,
        ),
      ),
    );
    expect(cache.activeLeases, 0);
  });
}
