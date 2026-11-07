import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  for (final box in [false, true]) {
    for (final cold in [false, true]) {
      testWidgets(
        '${box ? 'box' : 'sliver'} ${cold ? 'keeps cold layout work bounded' : 'delivers a cached visible page promptly'}',
        (tester) async {
          final cache = ForumBodyParagraphCache(
            maxEntries: 128,
            maxEstimatedBytes: 4 << 20,
          );
          final session = ForumBodyTextPageSession(
            document: const ForumBodyParser().parse(
              html: List.generate(24, (i) => '<p>line $i</p>').join(),
              sourceId: 'visible-flow',
              conversionIdentity: 'none',
            ),
            width: 200,
            height: 400,
            layoutId: 'visible-flow',
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
              maxPages: 4,
              maxFragments: 128,
              maxParagraphs: 32,
              maxTextCodeUnits: 4096,
              maxRuns: 128,
              maxIssuedLeases: 128,
            ),
          );
          addTearDown(cache.close);
          addTearDown(session.close);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          });
          for (var i = 0; i < 1000 && !session.isComplete; i++) {
            final step = session.advance(maxEvents: 16, maxLines: 4);
            expect(step.waitingForLayoutBudget, isFalse);
          }
          expect(session.isComplete, isTrue);
          expect(session.snapshot.length, 1);
          expect(
            session.snapshot.single.fragments.length,
            greaterThanOrEqualTo(24),
          );
          if (cold) {
            cache.clearUnpinned();
            expect(cache.entryCount, 0);
          } else {
            // The view must reuse real layouts and paint packets, rather than
            // waiting another frame for each already prepared paragraph.
            final preparation = session.openPagePreparation(0);
            for (var i = 0; i < 1000 && !preparation.isReady; i++) {
              preparation.advance(maxFragments: 1, maxParts: 8);
            }
            expect(preparation.isReady, isTrue);
            for (final fragment in preparation.takeFragments()) {
              fragment.close();
            }
            preparation.close();
          }
          final measuredBuilds = cache.layoutBuildCount;
          final errors = <Object>[];
          var ready = false;
          Widget slice(
            BuildContext context,
            ForumBodyTextPageSnapshot snapshot,
            int index,
            List<ForumBodyPreparedTextFragment> fragments,
          ) => ForumBodyTextPageSurface.prepared(
            snapshot: snapshot,
            pageIndex: index,
            layoutId: snapshot.layoutId,
            fragments: fragments,
            compactHeight: true,
          );
          final body = box
              ? ForumBodyFlowBox(
                  session: session,
                  prefix: session.snapshot,
                  onFailure: (error, _) => errors.add(error),
                  onReadyChanged: (value) => ready = value,
                  buildSlice: slice,
                )
              : ForumBodyFlowSliver(
                  session: session,
                  prefix: session.snapshot,
                  onFailure: (error, _) => errors.add(error),
                  onReadyChanged: (value) => ready = value,
                  buildSlice: slice,
                );
          var previous = cache.layoutBuildCount;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 200,
                    height: 400,
                    child: CustomScrollView(
                      slivers: [box ? SliverToBoxAdapter(child: body) : body],
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(cache.layoutBuildCount - previous, lessThanOrEqualTo(1));
          previous = cache.layoutBuildCount;
          final frames = cold ? 64 : 3;
          for (var i = 0; i < frames && !ready; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(cache.layoutBuildCount - previous, lessThanOrEqualTo(1));
            previous = cache.layoutBuildCount;
          }
          expect(ready, isTrue);
          if (!cold) {
            expect(cache.layoutBuildCount, measuredBuilds);
          }
          expect(errors, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(session.activeIssuedFragments, 0);
          expect(cache.activeLeases, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
