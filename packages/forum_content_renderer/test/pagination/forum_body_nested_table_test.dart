import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _html =
    '<p>before</p><table><tr><td>outer'
    '<div><table><tr><td width="120">nested A</td><td>'
    '<table><tr><td>deep B</td></tr></table>'
    '</td></tr></table></div>end'
    '</td></tr></table><p>after</p>';

ForumBodyTextPageSession _session(
  String html,
  ForumBodyParagraphCache cache, {
  double width = 240,
  int maxParagraphs = 64,
}) => ForumBodyTextPageSession(
  document: const ForumBodyParser().parse(
    html: html,
    sourceId: 'nested-table',
    conversionIdentity: 'none',
  ),
  reader: ForumBodyReaderStyle(
    textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
    fontRevision: 'nested-table',
    linkColor: Colors.blue,
    paragraphAfter: 0,
  ),
  cache: cache,
  layoutId: 'nested-table',
  width: width,
  height: 120,
  dedicatedTables: true,
  tableExtent: ForumBodyTableExtent.natural,
  limits: ForumBodyTextPageSessionLimits(
    maxPages: 64,
    maxFragments: 256,
    maxParagraphs: maxParagraphs,
    maxTextCodeUnits: 8192,
    maxRuns: 256,
    maxIssuedLeases: 32,
  ),
);

void _finish(ForumBodyTextPageSession session) {
  for (var i = 0; i < 20000 && !session.isComplete; i++) {
    final step = session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
  }
  expect(session.isComplete, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cell tables recursively compose with source-bound natural height', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 64,
      maxEstimatedBytes: 8 << 20,
    );
    final session = _session(_html, cache);
    addTearDown(cache.close);
    addTearDown(session.close);
    _finish(session);
    final outerPage = session.snapshot.singleWhere(
      (page) => page.table != null,
    );
    final outer = session.tableLayoutForPage(outerPage.index)!;
    expect(outer.size.height, greaterThan(30));
    expect(outer.size.height, lessThan(120));
    final copy = session.openWholeBodyCopy(maxCodeUnits: 8192, maxWork: 8192)!;
    for (var i = 0; !copy.isDone && i < 1000; i++) {
      copy.advance(maxWork: 1);
    }
    expect(
      copy.text?.replaceAll('\n', ''),
      'beforeouternested Adeep Bendafter',
    );
    copy.close();
    final nestedPage = outer.cells.single.snapshot.singleWhere(
      (p) => p.table != null,
    );
    final nested = outer.cells.single.tableLayoutForPage(nestedPage.index)!;
    expect(
      outer.cells.single.contentBounds.width,
      greaterThanOrEqualTo(nested.size.width),
    );
    session.close();
    expect(outer.isClosed, isTrue);
    expect(nested.isClosed, isTrue);
    expect(cache.activeLeases, 0);
  });

  test('table nesting has an explicit bounded source budget', () {
    final html = '${'<table><tr><td>' * 9}leaf${'</td></tr></table>' * 9}';
    final document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'depth',
      conversionIdentity: 'none',
    );
    expect(
      () => ForumBodyTableGrid.fromDocument(
        document,
        document.tableElements.first,
      ),
      throwsA(
        isA<ForumBodyTableException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyTableFailure.nestingLimit,
        ),
      ),
    );
    expect(
      ForumBodyTableGrid.fromDocument(
        document,
        document.tableElements[1],
      ).cells,
      hasLength(1),
    );
  });

  test(
    'nested text counts toward the outer budget and leaves a readable prefix',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 64,
        maxEstimatedBytes: 8 << 20,
      );
      final session = _session(_html, cache, maxParagraphs: 3);
      addTearDown(cache.close);
      addTearDown(session.close);
      expect(
        () => _finish(session),
        throwsA(
          isA<ForumBodyTableException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTableFailure.workLimit,
          ),
        ),
      );
      expect(session.snapshot, isNotEmpty);
      expect(session.snapshot.first.table, isNull);
      expect(session.activeIssuedTablePages, 0);
      expect(cache.activeLeases, 0);
    },
  );

  testWidgets(
    'nested cells paint and contribute source windows under the outer viewport',
    (tester) async {
      final cache = ForumBodyParagraphCache(
        maxEntries: 64,
        maxEstimatedBytes: 8 << 20,
      );
      const width = 80.0;
      final session = _session(_html, cache, width: width);
      final scroll = ScrollController();
      addTearDown(cache.close);
      addTearDown(session.close);
      addTearDown(scroll.dispose);
      _finish(session);
      final errors = <Object>[];
      final windows = <ForumBodyTableVisibleWindow>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            child: SizedBox(
              width: width,
              height: 120,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  ForumBodyFlowSliver(
                    session: session,
                    prefix: session.snapshot,
                    onFailure: (error, _) => errors.add(error),
                    onTableWindowChanged: (_, window) {
                      if (window != null) windows.add(window);
                    },
                    buildSlice: (context, snapshot, page, fragments) =>
                        ForumBodyTextPageSurface.prepared(
                          snapshot: snapshot,
                          pageIndex: page,
                          layoutId: snapshot.layoutId,
                          fragments: fragments,
                          compactHeight: true,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(errors, isEmpty);
      expect(windows, isNotEmpty);
      final before = windows.last;
      expect(
        before.slices.any(
          (slice) =>
              slice.fragments.any((f) => f.projection.text.contains('deep B')),
        ),
        isFalse,
      );
      final root = tester
          .widgetList<ForumBodyTableFlowViewport>(
            find.byType(ForumBodyTableFlowViewport),
          )
          .first;
      final area = root.layout.cells.single;
      final page = area.snapshot.singleWhere((p) => p.table != null);
      final grid = area.tableLayoutForPage(page.index)!;
      final target =
          area.contentBounds.left +
          page.table!.bounds.left +
          grid.cells.last.contentBounds.left;
      root.horizontalController.jumpTo(
        target.clamp(0.0, root.horizontalController.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      expect(before.isCurrent, isFalse);
      final window = windows.last;
      expect(window.isCurrent, isTrue);
      final deep = window.slices.singleWhere(
        (slice) =>
            slice.fragments.any((f) => f.projection.text.contains('deep B')),
      );
      expect(deep.clip.overlaps(deep.bounds), isTrue);
      expect(window.bounds.contains(deep.clip.center), isTrue);
      expect(find.byType(ForumBodyTableFlowViewport), findsNWidgets(3));
      final deepest = tester
          .elementList(find.byType(ForumBodyTableFlowViewport))
          .last;
      final inner = ForumBodyTableFlowViewport.borrowPaintedWindow(deepest)!;
      final point = ForumBodyFlowTextAnchor.firstVisibleInTable(inner)!;
      expect(point.anchor.path.startsWith(deep.area.element.path), isTrue);
      expect(point.anchor.text, 'd');
      final retired = tester
          .widgetList<ForumBodyTableFlowViewport>(
            find.byType(ForumBodyTableFlowViewport),
          )
          .last;
      await tester.pumpWidget(const SizedBox.shrink());
      retired.onFailure(
        StateError('retired nested callback'),
        StackTrace.current,
      );
      expect(errors, isEmpty);
      expect(window.isCurrent, isFalse);
      expect(inner.isCurrent, isFalse);
      expect(session.activeIssuedFragments, 0);
      expect(session.activeIssuedTablePages, 0);
      expect(cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
