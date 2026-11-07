import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  _invalidTransferTest();
  for (final nested in [false, true]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'cached ${nested ? 'nested' : 'three-column'} table paints all cells on first mount ($direction)',
        (tester) async {
          const row = '<tr><td>A</td><td>B</td><td>C</td></tr>';
          final html = nested
              ? '<table width="300"><tr><td><table width="280">$row</table></td></tr></table>'
              : '<table width="300">$row</table>';
          await _firstMount(tester, html, direction: direction);
        },
      );
    }
  }
  testWidgets('cached middle table window paints current rows on first mount', (
    tester,
  ) async {
    await _firstMount(
      tester,
      '<table width="300" cellpadding="0" cellspacing="0">'
      '<tr height="1200"><td>oldA</td><td>oldB</td><td>oldC</td></tr>'
      '<tr height="1200"><td valign="top">A</td><td valign="top">B</td><td valign="top">C</td></tr>'
      '</table>',
      offset: 1200,
    );
  });
  for (final direction in TextDirection.values) {
    testWidgets(
      'cached horizontal table return uses saved offset ($direction)',
      (tester) async {
        await _firstMount(
          tester,
          '<table width="900" cellpadding="0" cellspacing="0"><tr>'
          '<td width="300">A</td><td width="300">B</td><td width="300">C</td>'
          '</tr></table>',
          direction: direction,
          horizontalOffset: 300,
          expected: const ['B'],
        );
      },
    );
  }
  testWidgets('cached table attempt releases partial work on limit or miss', (
    tester,
  ) async {
    final cache = ForumBodyParagraphCache(
      maxEntries: 128,
      maxEstimatedBytes: 4 << 20,
    );
    final session = _session(
      '<table width="300"><tr><td>A</td><td>B</td><td>C</td></tr></table>',
      cache,
    );
    addTearDown(cache.close);
    addTearDown(session.close);
    _complete(session);
    final layout = session.tableLayoutForPage(0)!;
    final windows = [(layout: layout, bounds: Offset.zero & layout.size)];
    final builds = cache.layoutBuildCount;
    final pictures = cache.pictureBuildCount;
    expect(
      ForumBodyTablePreparedSlice.tryPrepareCachedWindows(
        windows,
        maxSteps: 5,
        timeBudget: const Duration(seconds: 1),
      ),
      isNull,
    );
    expect(cache.activeLeases, 0);
    expect(
      ForumBodyTablePreparedSlice.tryPrepareCachedWindows(
        windows,
        timeBudget: Duration.zero,
      ),
      isNull,
    );
    expect(cache.activeLeases, 0);
    final prepared = ForumBodyTablePreparedSlice.tryPrepareCachedWindows(
      windows,
      timeBudget: const Duration(seconds: 1),
    )!;
    expect(prepared, hasLength(3));
    expect(cache.activeLeases, greaterThan(0));
    for (final slice in prepared) {
      slice.close();
      slice.close();
    }
    expect(cache.activeLeases, 0);
    expect(cache.layoutBuildCount, builds);
    expect(cache.pictureBuildCount, pictures);
    cache.clearUnpinned();
    expect(
      ForumBodyTablePreparedSlice.tryPrepareCachedWindows(
        windows,
        timeBudget: const Duration(seconds: 1),
      ),
      isNull,
    );
    expect(cache.activeLeases, 0);
    expect(cache.layoutBuildCount, builds);
    expect(cache.pictureBuildCount, pictures);
  });
  testWidgets('cancelled nested table transfer does not keep retired leases', (
    tester,
  ) async {
    final cache = ForumBodyParagraphCache(
      maxEntries: 128,
      maxEstimatedBytes: 4 << 20,
    );
    final session = _session(
      '<table width="300"><tr><td><table width="280"><tr>'
      '<td>A</td><td>B</td><td>C</td></tr></table></td></tr></table>',
      cache,
    );
    addTearDown(cache.close);
    addTearDown(session.close);
    _complete(session);
    final layout = session.tableLayoutForPage(0)!;
    final windows = [(layout: layout, bounds: Offset.zero & layout.size)];
    final prepared = ForumBodyTablePreparedSlice.tryPrepareCachedWindows(
      windows,
      timeBudget: const Duration(seconds: 1),
    )!;
    expect(prepared, hasLength(4));
    expect(cache.activeLeases, greaterThan(0));
    session.close();
    for (final slice in prepared) {
      slice.close();
    }
    expect(cache.activeLeases, 0);
    expect(
      ForumBodyTablePreparedSlice.tryPrepareCachedWindows(windows),
      isNull,
    );
  });
}

// Kept separate from the normal mount cases so the expected build error cannot
// hide a resource leak behind session/cache teardown.
void _invalidTransferTest() {
  testWidgets('invalid duplicate transfer releases already adopted cells', (
    tester,
  ) async {
    final cache = ForumBodyParagraphCache(
      maxEntries: 128,
      maxEstimatedBytes: 4 << 20,
    );
    final session = _session(
      '<table width="300"><tr><td>A</td><td>B</td><td>C</td></tr></table>',
      cache,
    );
    final horizontal = ScrollController();
    addTearDown(cache.close);
    addTearDown(session.close);
    addTearDown(horizontal.dispose);
    _complete(session);
    final layout = session.tableLayoutForPage(0)!;
    final slices = [
      for (var i = 0; i < 2; i++)
        ...ForumBodyTablePreparedSlice.tryPrepareCachedWindows([
          (layout: layout, bounds: Offset.zero & layout.size),
        ], timeBudget: const Duration(seconds: 1))!,
    ];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ForumBodyTableFlowViewport(
          layout: layout,
          horizontalController: horizontal,
          initialSlices: slices,
          buildSlice: (_, _, _, _) => const SizedBox.shrink(),
          onFailure: (_, _) {},
        ),
      ),
    );
    expect(tester.takeException(), isA<StateError>());
    for (final slice in slices) {
      slice.close();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cache.activeLeases, 0);
    expect(session.activeIssuedFragments, 0);
  });
}

Future<void> _firstMount(
  WidgetTester tester,
  String html, {
  TextDirection direction = TextDirection.ltr,
  double offset = 0,
  double horizontalOffset = 0,
  List<String> expected = const ['A', 'B', 'C'],
}) async {
  final cache = ForumBodyParagraphCache(
    maxEntries: 128,
    maxEstimatedBytes: 4 << 20,
  );
  final session = _session(html, cache);
  final scroll = ScrollController(initialScrollOffset: offset);
  addTearDown(cache.close);
  addTearDown(session.close);
  addTearDown(scroll.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  _complete(session);
  expect(cache.activeLeases, 0);
  final errors = <Object>[];
  Widget body() => MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 100,
          child: SingleChildScrollView(
            controller: scroll,
            child: ForumBodyFlowBox(
              session: session,
              prefix: session.snapshot,
              initialTableOffset: (slice: 0, offset: horizontalOffset),
              onFailure: (error, _) => errors.add(error),
              buildSlice: (_, snapshot, index, fragments) =>
                  ForumBodyTextPageSurface.prepared(
                    snapshot: snapshot,
                    pageIndex: index,
                    layoutId: snapshot.layoutId,
                    fragments: fragments,
                    compactHeight: true,
                  ),
            ),
          ),
        ),
      ),
    ),
  );
  // Exercise the return path after a real first display. This also keeps cold
  // VM compilation outside the production cache lookup's 2ms time allowance.
  await tester.pumpWidget(body());
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(session.activeIssuedFragments, 0);
  expect(cache.activeLeases, 0);
  final builds = cache.layoutBuildCount;
  final pictures = cache.pictureBuildCount;
  Set<String> visible = {};
  // Wall-time admission may defer under parallel test/VM startup load. Retry
  // returns rather than claiming every lookup must fit regardless of that load.
  // The old post-frame-only path stays empty on every first mount.
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.pumpWidget(body());
    for (
      var frame = 0;
      frame < 10 && find.byType(ForumBodyTableFlowViewport).evaluate().isEmpty;
      frame++
    ) {
      await tester.pump();
    }
    expect(find.byType(ForumBodyTableFlowViewport), findsWidgets);
    final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
    visible = {};
    for (final e in find.byType(ForumBodyParagraphSurface).evaluate()) {
      final box = e.renderObject! as RenderBox;
      if ((box.localToGlobal(Offset.zero) & box.size).overlaps(viewport)) {
        visible.add(
          (e.widget as ForumBodyParagraphSurface).lease.content.projection.text,
        );
      }
    }
    if (visible.isNotEmpty) break;
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cache.activeLeases, 0);
  }
  expect(visible, unorderedEquals(expected));
  await tester.pumpAndSettle();
  for (final element in find.byType(ForumBodyParagraphSurface).evaluate()) {
    final box = element.renderObject! as RenderBox;
    final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
    if (!(box.localToGlobal(Offset.zero) & box.size).overlaps(viewport)) {
      continue;
    }
    final exclusions = tester.widgetList<ExcludeSemantics>(
      find.ancestor(
        of: find.byWidget(element.widget),
        matching: find.byType(ExcludeSemantics),
      ),
    );
    expect(exclusions.where((widget) => widget.excluding), isEmpty);
  }
  expect(cache.layoutBuildCount, builds);
  expect(cache.pictureBuildCount, pictures);
  expect(errors, isEmpty);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(session.activeIssuedFragments, 0);
  expect(session.activeIssuedTablePages, 0);
  expect(cache.activeLeases, 0);
  expect(tester.takeException(), isNull);
}

ForumBodyTextPageSession _session(String html, ForumBodyParagraphCache cache) =>
    ForumBodyTextPageSession(
      document: const ForumBodyParser().parse(
        html: html,
        sourceId: 'cached-table',
        conversionIdentity: 'none',
      ),
      width: 300,
      height: 200,
      layoutId: 'cached-table',
      tableExtent: ForumBodyTableExtent.natural,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
        fontRevision: 'ahem',
        linkColor: Colors.blue,
        paragraphAfter: 0,
      ),
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 128,
        maxFragments: 256,
        maxParagraphs: 128,
        maxTextCodeUnits: 4096,
        maxRuns: 512,
        maxIssuedLeases: 128,
      ),
    );

void _complete(ForumBodyTextPageSession session) {
  for (var step = 0; !session.isComplete && step < 10000; step++) {
    expect(
      session.advance(maxEvents: 32, maxLines: 8).waitingForLayoutBudget,
      false,
    );
  }
  expect(session.isComplete, true);
}
