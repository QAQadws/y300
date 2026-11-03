import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import 'test_support/emphasis_page_preparation_fixture.dart';

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);
ForumBodyTextPageSurface _surface(
  EmphasisPagePreparationFixture f,
  List<ForumBodyPreparedTextFragment> fragments, {
  Key? key,
  int page = 0,
  void Function(ForumBodyTextPageFragment, HtmlProjectedSourcePosition)? onTap,
}) => ForumBodyTextPageSurface.prepared(
  key: key,
  snapshot: f.snapshot,
  pageIndex: page,
  layoutId: f.snapshot.layoutId,
  fragments: fragments,
  onSourceTap: onTap,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    testWidgets(
      'page replay, source taps and visible-only semantics $direction',
      (tester) async {
        final f = EmphasisPagePreparationFixture(
              bodies: ['A<span style="visibility:hidden">Z</span>B'],
              direction: direction,
            ),
            job = f.open();
        f.finish(job);
        final fragments = job.takeFragments(),
            view = (fragments.single as ForumBodyPreparedEmphasisFragment).view;
        job.close();
        final before = (f.cache.layoutBuildCount, f.cache.pictureBuildCount),
            key = GlobalKey();
        final semantics = tester.ensureSemantics();
        try {
          var taps = 0;
          await tester.pumpWidget(
            _host(
              RepaintBoundary(
                key: key,
                child: _surface(
                  f,
                  fragments,
                  onTap: (_, position) {
                    expect(position.displayUtf16, inInclusiveRange(2, 3));
                    taps++;
                  },
                ),
              ),
            ),
          );
          final leaf = find.byType(ForumBodyEmphasisFragmentSurface);
          expect(leaf, findsOneWidget);
          expect(tester.getSemantics(leaf).label, 'AB');
          expect(tester.getSize(leaf), Size(view.width, view.height));
          final box = view.selectionBoxes(2, 3).first.toRect();
          await tester.tapAt(tester.getTopLeft(leaf) + box.center);
          expect(taps, 1);
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          Future<List<int>> pixels() async {
            final image = await boundary.toImage(pixelRatio: 3);
            try {
              return (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List().toList();
            } finally {
              image.dispose();
            }
          }

          final first = (await tester.runAsync(pixels))!;
          expect(first.any((v) => v != 0), isTrue);
          await tester.pump();
          expect(await tester.runAsync(pixels), first);
          expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), before);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(f.cache.activeLeases, 0);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
  testWidgets(
    'concurrent pages own distinct handles while sharing native scene storage',
    (tester) async {
      final f = EmphasisPagePreparationFixture(), first = f.open();
      f.finish(first);
      final a = first.takeFragments(), second = f.open();
      f.finish(second);
      final b = second.takeFragments(),
          before = (f.cache.layoutBuildCount, f.cache.pictureBuildCount);
      expect(f.cache.activeLeases, 4);
      await tester.pumpWidget(
        _host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _surface(f, a, key: const ValueKey('a')),
              _surface(f, b, key: const ValueKey('b')),
            ],
          ),
        ),
      );
      expect(find.byType(ForumBodyEmphasisFragmentSurface), findsNWidgets(2));
      await tester.pumpWidget(
        _host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [_surface(f, b, key: const ValueKey('b'))],
          ),
        ),
      );
      expect(f.cache.activeLeases, 2);
      expect(b.single.isActive, isTrue);
      expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), before);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'placement generation changes cancel old gestures without reacquiring fonts',
    (tester) async {
      final f = EmphasisPagePreparationFixture(), job = f.open();
      f.finish(job);
      final fragments = job.takeFragments(),
          view = (fragments.single as ForumBodyPreparedEmphasisFragment).view;
      var first = 0, second = 0;
      await tester.pumpWidget(
        _host(
          ForumBodyEmphasisFragmentSurface(
            view: view,
            interactionIdentity: 1,
            onSourceTap: (_) {
              first++;
            },
          ),
        ),
      );
      final point =
          tester.getTopLeft(find.byType(ForumBodyEmphasisFragmentSurface)) +
          view.selectionBoxes(0, 1).first.toRect().center;
      final gesture = await tester.startGesture(point);
      final before = (f.cache.layoutBuildCount, f.cache.pictureBuildCount);
      await tester.pumpWidget(
        _host(
          ForumBodyEmphasisFragmentSurface(
            view: view,
            interactionIdentity: 2,
            onSourceTap: (_) {
              second++;
            },
          ),
        ),
      );
      await gesture.up();
      expect(first + second, 0);
      await tester.tapAt(point);
      expect(second, 1);
      expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), before);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.cache.activeLeases, 0);
    },
  );
  testWidgets(
    'reader retirement invalidates queued taps and prevents late binding',
    (tester) async {
      final f = EmphasisPagePreparationFixture(), job = f.open();
      f.finish(job);
      final fragments = job.takeFragments();
      var taps = 0;
      await tester.pumpWidget(
        _host(
          _surface(
            f,
            fragments,
            onTap: (_, _) {
              taps++;
            },
          ),
        ),
      );
      final gesture = await tester.startGesture(const Offset(5, 5));
      f.close();
      await gesture.up();
      expect(taps, 0);
      expect(
        () => _surface(f, fragments),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
