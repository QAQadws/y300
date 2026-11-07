import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  for (final table in [false, true]) {
    testWidgets(
      'retained ${table ? 'table leaf' : 'flow slice'} avoids parent repaints',
      (tester) async {
        final cache = ForumBodyParagraphCache(
          maxEntries: 64,
          maxEstimatedBytes: 4 << 20,
        );
        final document = const ForumBodyParser().parse(
          html: table
              ? '<table width="100" cellspacing="0" cellpadding="0">'
                    '${List.generate(12, (i) => '<tr height="30"><td>row$i</td></tr>').join()}'
                    '</table>'
              : List.generate(12, (i) => '<p>${'x' * 100} $i</p>').join(),
          sourceId: 'repaint',
          conversionIdentity: 'none',
        );
        final session = ForumBodyTextPageSession(
          document: document,
          width: 100,
          height: 100,
          layoutId: 'repaint',
          tableExtent: ForumBodyTableExtent.natural,
          reader: ForumBodyReaderStyle(
            textStyle: const TextStyle(
              fontFamily: 'Ahem',
              fontSize: 10,
              height: 1,
            ),
            fontRevision: 'ahem',
            linkColor: Colors.blue,
            paragraphAfter: 0,
          ),
          cache: cache,
          limits: const ForumBodyTextPageSessionLimits(
            maxPages: 64,
            maxFragments: 128,
            maxParagraphs: 32,
            maxTextCodeUnits: 4096,
            maxRuns: 128,
            maxIssuedLeases: 128,
          ),
        );
        final scroll = ScrollController();
        final background = ValueNotifier<Color>(Colors.white);
        addTearDown(cache.close);
        addTearDown(session.close);
        addTearDown(scroll.dispose);
        addTearDown(background.dispose);
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        for (var step = 0; step < 2000 && !session.isComplete; step++) {
          expect(
            session.advance(maxEvents: 16, maxLines: 4).waitingForLayoutBudget,
            false,
          );
        }
        expect(session.isComplete, true);
        final paints = <Object, int>{};
        final fragmentsBySlice =
            <Object, List<ForumBodyPreparedTextFragment>>{};
        Widget slice(
          ForumBodyTextPageSnapshot snapshot,
          int page,
          List<ForumBodyPreparedTextFragment> fragments,
          Object key,
        ) {
          fragmentsBySlice[key] = fragments;
          return _PaintCounter(
            onPaint: () => paints.update(key, (n) => n + 1, ifAbsent: () => 1),
            child: ForumBodyTextPageSurface.prepared(
              snapshot: snapshot,
              pageIndex: page,
              layoutId: snapshot.layoutId,
              fragments: fragments,
              compactHeight: true,
            ),
          );
        }

        final Widget body;
        if (table) {
          final lease = session.acquireTablePage(0)!;
          final horizontal = ScrollController();
          addTearDown(lease.close);
          addTearDown(horizontal.dispose);
          body = ForumBodyTableFlowViewport(
            layout: lease.layout,
            horizontalController: horizontal,
            preloadExtentFactor: 1,
            buildSlice: (_, area, page, fragments) =>
                slice(area.snapshot, page, fragments, (area, page)),
            onFailure: (error, _) => fail('$error'),
          );
        } else {
          body = ForumBodyFlowBox(
            session: session,
            prefix: session.snapshot,
            preloadExtentFactor: 1,
            buildSlice: (_, snapshot, page, fragments) =>
                slice(snapshot, page, fragments, page),
            onFailure: (error, _) => fail('$error'),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 100,
                height: 70,
                child: SingleChildScrollView(
                  controller: scroll,
                  child: ValueListenableBuilder<Color>(
                    valueListenable: background,
                    builder: (_, color, child) =>
                        ColoredBox(color: color, child: child),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(paints, isNotEmpty);
        final first = paints.keys.first;
        final original = fragmentsBySlice[first]!;
        final before = paints[first]!;
        background.value = Colors.yellow;
        await tester.pump();
        scroll.jumpTo(1);
        await tester.pumpAndSettle();
        expect(identical(fragmentsBySlice[first], original), true);
        expect(original.every((fragment) => fragment.isActive), true);
        expect(paints[first], before);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(session.activeIssuedFragments, 0);
        expect(cache.activeLeases, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _PaintCounter extends SingleChildRenderObjectWidget {
  const _PaintCounter({required this.onPaint, required super.child});
  final VoidCallback onPaint;

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _CounterBox(onPaint);

  @override
  void updateRenderObject(BuildContext context, _CounterBox renderObject) {
    renderObject.onPaint = onPaint;
  }
}

final class _CounterBox extends RenderProxyBox {
  _CounterBox(this.onPaint);
  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}
