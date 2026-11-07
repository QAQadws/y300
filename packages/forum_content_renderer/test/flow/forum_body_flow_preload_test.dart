import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  for (final leaseLimit in [6, 128]) {
    testWidgets(
      'offscreen neighbor is ready before entry and yields to visible demand (leases=$leaseLimit)',
      (tester) async {
        final cache = ForumBodyParagraphCache(
          maxEntries: 128,
          maxEstimatedBytes: 4 << 20,
        );
        final scope = ForumBodyPreloadScope();
        final scroll = ScrollController();
        final session = ForumBodyTextPageSession(
          document: const ForumBodyParser().parse(
            html: List.generate(12, (i) => '<p>${'x' * 100} $i</p>').join(),
            sourceId: 'preload',
            conversionIdentity: 'none',
          ),
          width: 100,
          height: 100,
          layoutId: 'preload',
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
          limits: ForumBodyTextPageSessionLimits(
            maxPages: 64,
            maxFragments: 128,
            maxParagraphs: 32,
            maxTextCodeUnits: 4096,
            maxRuns: 128,
            maxIssuedLeases: leaseLimit,
          ),
        );
        addTearDown(cache.close);
        addTearDown(session.close);
        addTearDown(scope.dispose);
        addTearDown(scroll.dispose);
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        for (var i = 0; i < 2000 && !session.isComplete; i++) {
          expect(
            session.advance(maxEvents: 16, maxLines: 4).waitingForLayoutBudget,
            false,
          );
        }
        expect(session.isComplete, true);
        expect(session.snapshot.length, greaterThan(6));
        final prepared = <int, List<ForumBodyPreparedTextFragment>>{};
        final errors = <Object>[];
        var visibleReady = false;
        final visibleConsumer = Object();
        scope.setVisibleWork(visibleConsumer, true);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 100,
                  height: 200,
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: Column(
                      children: [
                        const SizedBox(height: 250),
                        ForumBodyFlowBox(
                          session: session,
                          prefix: session.snapshot,
                          preloadExtentFactor: 1,
                          preloadScope: scope,
                          onFailure: (error, _) => errors.add(error),
                          onReadyChanged: (value) => visibleReady = value,
                          buildSlice: (_, snapshot, index, fragments) {
                            prepared[index] = fragments;
                            return ForumBodyTextPageSurface.prepared(
                              snapshot: snapshot,
                              pageIndex: index,
                              layoutId: snapshot.layoutId,
                              fragments: fragments,
                              compactHeight: true,
                            );
                          },
                        ),
                        const SizedBox(height: 1200),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          prepared,
          isEmpty,
          reason: 'Visible demand takes the shared resource budget first.',
        );
        scope.setVisibleWork(visibleConsumer, false);
        for (var i = 0; i < 20 && prepared[0] == null; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final first = prepared[0]!;
        expect(first, isNotEmpty);
        expect(first.every((f) => f.isActive), true);
        expect(
          visibleReady,
          false,
          reason: 'Preloading is not a visible-ready report.',
        );
        scroll.jumpTo(100);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(visibleReady, true);
        expect(
          prepared[0],
          same(first),
          reason: 'Entering the viewport keeps its ready delivery.',
        );
        scroll.jumpTo(0);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        scope.pause();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(session.activeIssuedFragments, 0);
        expect(scope.mayPreload, false);
        scroll.jumpTo(1000);
        for (var i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(first.every((f) => !f.isActive), true);
        expect(session.activeIssuedFragments, lessThanOrEqualTo(leaseLimit));
        expect(errors, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(session.activeIssuedFragments, 0);
        expect(cache.activeLeases, 0);
        expect(scope.mayPreload, true);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
