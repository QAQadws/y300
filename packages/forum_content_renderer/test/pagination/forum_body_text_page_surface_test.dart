import 'dart:ui' as ui;

import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

final class _Fixture {
  _Fixture({
    String html = '<p>aa<br>bb<br>cc<br>dd</p>',
    String sourceId = 'page-surface',
  }) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: sourceId,
      conversionIdentity: 'none',
    );
    cache = ForumBodyParagraphCache(maxEntries: 8, maxEstimatedBytes: 1 << 20);
    addTearDown(cache.close);
  }
  late final ForumBodyDocument document;
  late final ForumBodyParagraphCache cache;
  ForumBodyParagraphContent content(
    int index, {
    double fontSize = 10,
    String fontRevision = 'ahem',
  }) => const ForumBodyParagraphContentBuilder().build(
    document: document,
    path: '$index',
    styles: const ForumBodyStyleResolver().resolve(
      document,
      ForumBodyReaderStyle(
        textStyle: TextStyle(
          fontSize: fontSize,
          height: 1,
          fontFamily: 'Ahem',
          color: const Color(0xff000000),
        ),
        fontRevision: fontRevision,
        linkColor: const Color(0xff0000ff),
      ),
    ),
  );
  ForumBodyParagraphLease lease(
    int index, {
    double width = 100,
    double fontSize = 10,
    String fontRevision = 'ahem',
  }) => cache.acquire(
    content: content(index, fontSize: fontSize, fontRevision: fontRevision),
    width: width,
  );
  ForumBodyTextPageSnapshot plan({
    String id = 'generation-1',
    double width = 100,
    double height = 20,
    int paragraphs = 1,
    double gap = 0,
    List<double>? widths,
    List<double>? lefts,
    List<double>? befores,
  }) {
    final composer = ForumBodyTextPageComposer(
      identity: document.identity,
      layoutId: id,
      width: width,
      height: height,
      maxPages: 20,
      maxFragments: 40,
    );
    try {
      for (var index = 0; index < paragraphs; index++) {
        composer.append(
          lease: lease(index, width: widths?[index] ?? width),
          paragraphIndex: index,
          left: lefts?[index] ?? 0,
          spaceBefore: befores?[index] ?? 3,
          spaceAtPageStart: gap,
        );
        while (!composer.needsInput) {
          composer.advance(maxLines: 2);
        }
      }
      composer.finish();
      return composer.snapshot;
    } finally {
      composer.close();
    }
  }
}

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

ForumBodyTextPageSurface _surface(
  ForumBodyTextPageSnapshot plan,
  List<ForumBodyParagraphLease> leases, {
  int page = 0,
  void Function(ForumBodyTextPageFragment, HtmlProjectedSourcePosition)? onTap,
}) => ForumBodyTextPageSurface(
  snapshot: plan,
  pageIndex: page,
  layoutId: plan.layoutId,
  leases: leases,
  onSourceTap: onTap,
);

Future<List<int>> _pagePixels(RenderRepaintBoundary boundary) async {
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List().toList();
  } finally {
    image.dispose();
  }
}

void main() {
  testWidgets('a grapheme across a link seam is announced once as text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = _Fixture(
        html: '<p><a href="/read">Read e</a>\u0301 here</p>',
      );
      final plan = fixture.plan(width: 400, height: 40, befores: [0]);
      await tester.pumpWidget(
        _host(
          ForumBodyTextPageSurface(
            snapshot: plan,
            pageIndex: 0,
            layoutId: plan.layoutId,
            leases: [fixture.lease(0, width: 400)],
            onLinkTap: (_) {},
          ),
        ),
      );
      final link = tester.getSemantics(find.bySemanticsLabel('Read '));
      final ordered = link.parent!.debugListChildrenInOrder(
        DebugSemanticsDumpOrder.traversalOrder,
      );
      expect(ordered.map((node) => node.label), ['Read ', 'e\u0301', ' here']);
      expect(ordered[0].getSemanticsData().flagsCollection.isLink, isTrue);
      expect(ordered[1].getSemanticsData().flagsCollection.isLink, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('linked heading exposes logical roles, actions and focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = _Fixture(
        html:
            '<h2>Before<a href="/same"><span>First</span><b>Link</b></a>'
            '<a href="/same">Again</a>'
            '<a href="/hidden" style="visibility:hidden">Hidden</a>After</h2>',
      );
      final first = fixture.plan(width: 400, height: 50, befores: [0]);
      final next = fixture.plan(
        id: 'generation-2',
        width: 400,
        height: 50,
        befores: [0],
      );
      final lease = fixture.lease(0, width: 400);
      final opened = <String>[];
      Widget host(ForumBodyTextPageSnapshot snapshot, {bool enabled = true}) =>
          MaterialApp(
            home: Scaffold(
              body: _host(
                ForumBodyTextPageSurface(
                  snapshot: snapshot,
                  pageIndex: 0,
                  layoutId: snapshot.layoutId,
                  leases: [lease],
                  onLinkTap: enabled ? opened.add : null,
                ),
              ),
            ),
          );
      SemanticsNode node(String label) =>
          tester.getSemantics(find.bySemanticsLabel(label));
      await tester.pumpWidget(host(first));
      expect(find.bySemanticsLabel('BeforeFirstLinkAgainAfter'), findsNothing);
      expect(find.bySemanticsLabel('Hidden'), findsNothing);
      final link = node('FirstLink');
      expect(link.getSemanticsData().flagsCollection.isLink, isTrue);
      expect(link.getSemanticsData().flagsCollection.isHeader, isTrue);
      expect(
        node('Before').getSemanticsData().flagsCollection.isHeader,
        isTrue,
      );
      expect(
        link.parent!
            .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
            .map((child) => child.label),
        ['Before', 'FirstLink', 'Again', 'After'],
      );
      final action = link.getSemanticsData();
      expect(action.hasAction(ui.SemanticsAction.tap), isTrue);
      link.owner!.performAction(link.id, ui.SemanticsAction.tap);
      expect(opened, ['/same']);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        node('FirstLink').getSemanticsData().flagsCollection.isFocused,
        ui.Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        node('Again').getSemanticsData().flagsCollection.isFocused,
        ui.Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(opened, ['/same', '/same', '/same']);

      final retiredAction = tester
          .widget<Semantics>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.label == 'Again',
            ),
          )
          .properties
          .onTap!;
      await tester.pumpWidget(host(next));
      retiredAction();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, hasLength(3));
      await tester.pumpWidget(host(next, enabled: false));
      expect(
        find.bySemanticsLabel('BeforeFirstLinkAgainAfter'),
        findsOneWidget,
      );
      expect(lease.isActive, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.cache.activeLeases, 0);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('links use their painted glyphs and retire with the page', (
    tester,
  ) async {
    final fixture = _Fixture(
      html:
          '<p>ab<a href="/first">cd</a>ef'
          '<a href="/hidden" style="visibility:hidden">gh</a></p>',
    );
    final first = fixture.plan(befores: [0]);
    final second = fixture.plan(id: 'generation-2', befores: [0]);
    final lease = fixture.lease(0);
    Offset glyph(int index, double fraction) {
      final box = lease.layout.selectionBoxes(index, index + 1).single;
      return Offset(
        box.left + (box.right - box.left) * fraction,
        (box.top + box.bottom) / 2,
      );
    }

    final links = <String>[];
    var outerTaps = 0, longPresses = 0, drags = 0;
    Widget host(ForumBodyTextPageSnapshot snapshot) => _host(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => outerTaps++,
        onHorizontalDragEnd: (_) => drags++,
        child: ForumBodyTextPageSurface(
          snapshot: snapshot,
          pageIndex: 0,
          layoutId: snapshot.layoutId,
          leases: [lease],
          onLinkTap: links.add,
          onSourceLongPress: (_, _) => longPresses++,
        ),
      ),
    );

    await tester.pumpWidget(host(first));
    await tester.tapAt(glyph(1, .9)); // Just before the link.
    await tester.tapAt(glyph(3, .9)); // Caret is already at the link's end.
    await tester.tapAt(glyph(4, .1));
    await tester.tapAt(glyph(6, .5));
    await tester.tapAt(const Offset(90, 5));
    expect(links, ['/first']);
    expect(outerTaps, 4);

    await tester.longPressAt(glyph(2, .5));
    await tester.dragFrom(glyph(2, .5), const Offset(50, 0));
    expect(longPresses, 1);
    expect(drags, 1);
    expect(links, ['/first']);

    final stale = await tester.startGesture(glyph(2, .5));
    await tester.pumpWidget(host(second));
    await stale.up();
    await tester.pump();
    expect(links, ['/first']);
    await tester.tapAt(glyph(2, .5));
    expect(links, ['/first', '/first']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.cache.activeLeases, 0);
  });

  testWidgets(
    'a padding-only page paints without a paragraph lease or synthetic text',
    (tester) async {
      final fixture = _Fixture(html: '');
      final composer = ForumBodyTextPageComposer(
        identity: fixture.document.identity,
        layoutId: 'blank-padding',
        width: 100,
        height: 20,
        maxPages: 2,
        maxFragments: 1,
      );
      addTearDown(composer.close);
      composer.appendPadding(20);
      composer.advancePadding();
      composer.finish();
      var taps = 0;
      await tester.pumpWidget(
        _host(_surface(composer.snapshot, [], onTap: (_, _) => taps++)),
      );
      expect(
        tester.getSize(find.byType(ForumBodyTextPageSurface)),
        const Size(100, 20),
      );
      expect(find.byType(ForumBodyParagraphSurface), findsNothing);
      await tester.tapAt(const Offset(1, 5));
      expect(taps, 0);
      expect(fixture.cache.layoutBuildCount, 0);
      expect(fixture.cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'overlapping fragments paint and hit in actual page order without reshaping',
    (tester) async {
      final fixture = _Fixture(html: '<p>aa</p><p>bb</p>');
      final plan = fixture.plan(height: 40, paragraphs: 2, befores: [0, -5]);
      expect(plan.single.fragments.map((fragment) => fragment.top), [0, 5]);
      expect(plan.single.usedHeight, 15);
      final leases = [fixture.lease(0), fixture.lease(1)];
      final key = GlobalKey();
      final hits = <(int, int)>[];
      await tester.pumpWidget(
        _host(
          RepaintBoundary(
            key: key,
            child: _surface(
              plan,
              leases,
              onTap: (fragment, position) =>
                  hits.add((fragment.paragraphIndex, position.sourceRune)),
            ),
          ),
        ),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      leases[0].layout.fragment(0, 1).paint(canvas, Offset.zero);
      leases[1].layout.fragment(0, 1).paint(canvas, const Offset(0, 5));
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final reference = await picture.toImage(100, 40);
        try {
          expect(
            await _pagePixels(
              tester.renderObject<RenderRepaintBoundary>(find.byKey(key)),
            ),
            (await reference.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List().toList(),
          );
        } finally {
          reference.dispose();
          picture.dispose();
        }
      });
      await tester.tapAt(const Offset(1, 7));
      expect(hits, [(1, 2)]);
      expect(fixture.cache.layoutBuildCount, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.cache.activeLeases, 0);
    },
  );

  testWidgets(
    'page paints numeric placements using shared paragraph layouts and current source coordinates',
    (tester) async {
      final fixture = _Fixture(html: '<p>aa</p><p>bb</p>');
      final plan = fixture.plan(
        width: 120,
        height: 40,
        paragraphs: 2,
        gap: 5,
        widths: [80, 70],
        lefts: [10, 30],
      );
      final leases = [fixture.lease(0, width: 80), fixture.lease(1, width: 70)];
      final key = GlobalKey();
      final hits = <(int, int)>[];
      await tester.pumpWidget(
        _host(
          RepaintBoundary(
            key: key,
            child: _surface(
              plan,
              leases,
              onTap: (fragment, position) =>
                  hits.add((fragment.paragraphIndex, position.sourceRune)),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(ForumBodyTextPageSurface)),
        const Size(120, 40),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (final (index, fragment) in plan.single.fragments.indexed) {
        leases[index].layout
            .fragment(fragment.startLine, fragment.endLine)
            .paint(canvas, Offset(fragment.left, fragment.top));
      }
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final reference = await picture.toImage(120, 40);
        try {
          expect(
            await _pagePixels(
              tester.renderObject<RenderRepaintBoundary>(find.byKey(key)),
            ),
            (await reference.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List().toList(),
          );
        } finally {
          reference.dispose();
          picture.dispose();
        }
      });
      await tester.tapAt(const Offset(31, 23));
      expect(hits, [(1, 2)]);
      expect(fixture.cache.layoutBuildCount, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.cache.activeLeases, 0);
    },
  );

  testWidgets(
    'concurrent pages use separate leases over the same actual native layout',
    (tester) async {
      final fixture = _Fixture();
      final plan = fixture.plan();
      final first = fixture.lease(0);
      final second = fixture.lease(0);
      final hits = <int>[];
      await tester.pumpWidget(
        _host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _surface(plan, [first]),
              _surface(
                plan,
                [second],
                page: 1,
                onTap: (_, position) => hits.add(position.sourceRune),
              ),
            ],
          ),
        ),
      );
      await tester.tapAt(const Offset(101, 5));
      expect(hits, [6]);
      expect(first.layout, same(second.layout));
      expect(fixture.cache.layoutBuildCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.cache.activeLeases, 0);
    },
  );

  testWidgets(
    'generation and placement changes cancel a pending tap without reshaping',
    (tester) async {
      for (final (id, gap) in [('generation-2', 0.0), ('generation-1', 5.0)]) {
        final fixture = _Fixture(html: '<p>aa</p>');
        final firstPlan = fixture.plan(height: 30);
        final nextPlan = fixture.plan(id: id, height: 30, gap: gap);
        final lease = fixture.lease(0);
        var taps = 0;
        await tester.pumpWidget(
          _host(_surface(firstPlan, [lease], onTap: (_, _) => taps++)),
        );
        final gesture = await tester.startGesture(const Offset(1, 5));
        await tester.pumpWidget(
          _host(_surface(nextPlan, [lease], onTap: (_, _) => taps++)),
        );
        await gesture.up();
        await tester.pump();
        expect(taps, 0);
        await tester.tapAt(Offset(1, gap + 5));
        expect(taps, 1);
        expect(fixture.cache.layoutBuildCount, 1);
        expect(fixture.cache.activeLeases, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(fixture.cache.activeLeases, 0);
      }
    },
  );

  testWidgets(
    'reusing a lease for the next page retires its previous gesture and callback',
    (tester) async {
      final fixture = _Fixture();
      final plan = fixture.plan();
      final lease = fixture.lease(0);
      final hits = <(int, int)>[];
      await tester.pumpWidget(
        _host(
          _surface(plan, [
            lease,
          ], onTap: (_, position) => hits.add((0, position.sourceRune))),
        ),
      );
      final gesture = await tester.startGesture(const Offset(1, 5));
      await tester.pumpWidget(
        _host(
          _surface(
            plan,
            [lease],
            page: 1,
            onTap: (_, position) => hits.add((1, position.sourceRune)),
          ),
        ),
      );
      await gesture.up();
      expect(hits, isEmpty);
      await tester.tapAt(const Offset(1, 5));
      expect(hits, [(1, 6)]);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'binding rejects a wrong generation, identity, count or geometry without taking ownership',
    () {
      final fixture = _Fixture();
      final plan = fixture.plan();
      final lease = fixture.lease(0);
      addTearDown(lease.release);
      expect(
        () => ForumBodyTextPageSurface(
          snapshot: plan,
          pageIndex: 0,
          layoutId: 'retired',
          leases: [lease],
        ),
        throwsA(
          isA<ForumBodyTextPageSurfaceException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageSurfaceFailure.generation,
          ),
        ),
      );
      expect(
        () => _surface(plan, []),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      final foreign = _Fixture(sourceId: 'foreign');
      final foreignLease = foreign.lease(0);
      addTearDown(foreignLease.release);
      expect(
        () => _surface(plan, [foreignLease]),
        throwsA(
          isA<ForumBodyTextPageSurfaceException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageSurfaceFailure.identity,
          ),
        ),
      );
      for (final candidate in [
        fixture.lease(0, width: 80),
        fixture.lease(0, fontSize: 20),
        fixture.lease(0, fontRevision: 'late-font'),
      ]) {
        addTearDown(candidate.release);
        expect(
          () => _surface(plan, [candidate]),
          throwsA(isA<ForumBodyTextPageSurfaceException>()),
        );
        expect(candidate.isActive, isTrue);
      }
      expect(lease.isActive, isTrue);
      expect(foreignLease.isActive, isTrue);
      final two = _Fixture(html: '<p>aa</p><p>bb</p>');
      final twoPlan = two.plan(height: 40, paragraphs: 2);
      final duplicate = two.lease(0);
      addTearDown(duplicate.release);
      expect(
        () => _surface(twoPlan, [duplicate, duplicate]),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      expect(duplicate.isActive, isTrue);
    },
  );

  testWidgets(
    'viewport mismatch is explicit and leaves unmounted leases with the caller',
    (tester) async {
      final fixture = _Fixture();
      final plan = fixture.plan();
      final lease = fixture.lease(0);
      addTearDown(lease.release);
      await tester.pumpWidget(
        _host(SizedBox(width: 50, child: _surface(plan, [lease]))),
      );
      expect(tester.takeException(), isA<ForumBodyTextPageSurfaceException>());
      expect(lease.isActive, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'late mounting after native owner retirement cannot paint or emit a source tap',
    (tester) async {
      final fixture = _Fixture();
      final plan = fixture.plan();
      final lease = fixture.lease(0);
      var taps = 0;
      final prepared = _surface(plan, [lease], onTap: (_, _) => taps++);
      fixture.cache.close();
      await tester.pumpWidget(_host(prepared));
      await tester.tapAt(const Offset(1, 5));
      expect(tester.takeException(), isNull);
      expect(taps, 0);
      expect(fixture.cache.activeLeases, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
