import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Fixture {
  _Fixture(
    String html, {
    double height = 30,
    int fragments = 100,
    ForumBodyPageColumns columns = const ForumBodyPageColumns(),
    double width = 100,
  }) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'block-background',
      conversionIdentity: 'none',
    );
    cache = ForumBodyParagraphCache(maxEntries: 8, maxEstimatedBytes: 1 << 20);
    session = ForumBodyTextPageSession(
      document: document,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
        paragraphAfter: 0,
      ),
      cache: cache,
      limits: ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: fragments,
        maxParagraphs: 100,
        maxTextCodeUnits: 10000,
        maxRuns: 1000,
        maxIssuedLeases: 32,
      ),
      layoutId: 'generation',
      width: width,
      height: height,
      columns: columns,
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
  }
  late final ForumBodyDocument document;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  void drain({int? pages}) {
    var calls = 0;
    while (!session.isComplete &&
        (pages == null || session.snapshot.length < pages)) {
      if (++calls > 10000) fail('Background flow did not finish');
      final step = session.advance(maxEvents: 1, maxLines: 1);
      expect(step.madeProgress, isTrue);
      expect(step.pagesPublished, lessThanOrEqualTo(1));
      expect(step.flowWorkDone, lessThanOrEqualTo(1));
    }
  }

  List<ForumBodyPreparedTextFragment> prepare(int page) {
    final job = session.openPagePreparation(page);
    try {
      for (var i = 0; !job.isReady && i < 1000; i++) {
        job.advance(maxFragments: 1, maxParts: 1);
      }
      expect(job.isReady, isTrue);
      return job.takeFragments();
    } finally {
      job.close();
    }
  }
}

Rect _rect(ForumBodyTextPageBackground box) =>
    Rect.fromLTWH(box.left, box.top, box.width, box.height);

Future<Uint8List> _pagePixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(key))
          .toImage(pixelRatio: 1);
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;

int _rgbCount(Uint8List pixels, int rgb) {
  var count = 0;
  for (var index = 0; index < pixels.length; index += 4) {
    final value =
        (pixels[index] << 16) | (pixels[index + 1] << 8) | pixels[index + 2];
    if (value == rgb) count++;
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (name, source, buildsInk) in [
    (
      'ruby container',
      '<p><ruby style="background-color:#ff0000;color:transparent;font-size:20px">'
          '<rb>AB</rb><rt>a</rt></ruby> plain</p>',
      false,
    ),
    (
      'paragraph',
      '<p><span style="background-color:#ff0000;color:transparent;line-height:1.6">'
          'AB<b style="color:#0022ff;text-decoration:underline">CD</b>EF</span> plain</p>',
      true,
    ),
  ]) {
    testWidgets('$name background overrides reuse the mounted native page', (
      tester,
    ) async {
      final f = _Fixture(source, height: 70);
      f.drain();
      final snapshot = f.session.snapshot;
      final fragments = f.prepare(0);
      if (buildsInk) {
        expect(fragments.single, isA<ForumBodyPreparedParagraphFragment>());
      } else {
        final inline = fragments
            .whereType<ForumBodyPreparedInlineFragment>()
            .single;
        expect(inline.view.containerBackgrounds, hasLength(1));
      }
      final surface = ForumBodyTextPageSurface.prepared(
        snapshot: snapshot,
        pageIndex: 0,
        layoutId: snapshot.layoutId,
        fragments: fragments,
      );
      final key = GlobalKey();
      final body = RepaintBoundary(key: key, child: surface);
      Future<Uint8List> show({Color? color, double radius = 0}) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: ForumBodyTextBackgroundStyle(
                color: color,
                borderRadius: radius,
                child: body,
              ),
            ),
          ),
        );
        return _pagePixels(tester, key);
      }

      final authored = await show();
      final element = tester.element(find.byWidget(surface));
      final work = (
        f.cache.layoutBuildCount,
        f.cache.pictureBuildCount,
        f.cache.activeLeases,
      );
      final authoredBytes = f.cache.estimatedRetainedBytes;
      expect(_rgbCount(authored, 0xff0000), greaterThan(0));
      expect(_rgbCount(authored, 0x00ff00), 0);
      const green = Color(0xff00ff00);
      final square = await show(color: green);
      expect(f.cache.layoutBuildCount, work.$1 + (buildsInk ? 1 : 0));
      final bytes = f.cache.estimatedRetainedBytes;
      expect(bytes, buildsInk ? greaterThan(authoredBytes) : authoredBytes);
      final rounded = await show(color: green, radius: 9);
      expect(_rgbCount(square, 0x00ff00), _rgbCount(authored, 0xff0000));
      expect(_rgbCount(square, 0xff0000), 0);
      expect(_rgbCount(rounded, 0x00ff00), greaterThan(0));
      expect(
        _rgbCount(rounded, 0x00ff00),
        lessThan(_rgbCount(square, 0x00ff00)),
      );
      if (buildsInk) {
        final authoredInk = _rgbCount(authored, 0x0022ff);
        expect(authoredInk, greaterThan(0));
        expect(_rgbCount(rounded, 0x0022ff), authoredInk);
      }
      expect(await show(), orderedEquals(authored));
      expect(await show(color: green), orderedEquals(square));
      expect(tester.element(find.byWidget(surface)), same(element));
      expect(
        (
          f.cache.layoutBuildCount,
          f.cache.pictureBuildCount,
          f.cache.activeLeases,
        ),
        (work.$1 + (buildsInk ? 1 : 0), work.$2, work.$3),
      );
      expect(f.cache.estimatedRetainedBytes, bytes);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.cache.activeLeases, 0);
      f.cache.clearUnpinned();
      expect(f.cache.estimatedRetainedBytes, 0);
    });
  }

  testWidgets('ruby base and annotation use one shared styled band recording', (
    tester,
  ) async {
    final f = _Fixture(
      '<p>before <ruby><rb style="background:#ff0000;color:transparent">'
      'AB</rb><rt style="background:#0000ff;color:transparent">xy</rt></ruby> after</p>',
      height: 70,
    );
    f.drain();
    final snapshot = f.session.snapshot;
    final fragments = f.prepare(0);
    final inline = fragments
        .whereType<ForumBodyPreparedInlineFragment>()
        .single;
    final bands = inline.nativeLeases
        .whereType<ForumBodyTextBandChildLease>()
        .where((lease) => lease.content.hasSolidTextBackground)
        .toList();
    expect(
      bands.map((lease) => lease.content.projection.text),
      unorderedEquals(['AB', 'xy']),
    );
    expect(
      bands.map((lease) => lease.nativeInputIdentity).toSet(),
      hasLength(1),
    );
    final surface = ForumBodyTextPageSurface.prepared(
      snapshot: snapshot,
      pageIndex: 0,
      layoutId: snapshot.layoutId,
      fragments: fragments,
    );
    final key = GlobalKey();
    final body = RepaintBoundary(key: key, child: surface);
    Future<Uint8List> show({Color? color, double radius = 0}) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextBackgroundStyle(
              color: color,
              borderRadius: radius,
              child: body,
            ),
          ),
        ),
      );
      return _pagePixels(tester, key);
    }

    final authored = await show();
    final red = _rgbCount(authored, 0xff0000);
    final blue = _rgbCount(authored, 0x0000ff);
    expect(red, greaterThan(0));
    expect(blue, greaterThan(0));
    final builds = f.cache.layoutBuildCount;
    final pictures = f.cache.pictureBuildCount;
    final preparedPictures = f.cache.preparedPictureCount;
    final handles = f.cache.activeLeases;
    final bytes = f.cache.estimatedRetainedBytes;
    final element = tester.element(find.byWidget(surface));
    final square = await show(color: const Color(0xff00ff00));
    expect(_rgbCount(square, 0x00ff00), red + blue);
    expect(_rgbCount(square, 0xff0000) + _rgbCount(square, 0x0000ff), 0);
    final rounded = await show(radius: 5);
    expect(_rgbCount(rounded, 0xff0000), inExclusiveRange(0, red));
    expect(_rgbCount(rounded, 0x0000ff), inExclusiveRange(0, blue));
    expect(await show(), orderedEquals(authored));
    expect(tester.element(find.byWidget(surface)), same(element));
    expect(f.cache.layoutBuildCount, builds + 1);
    expect(f.cache.pictureBuildCount, pictures + 1);
    expect(f.cache.preparedPictureCount, preparedPictures + 1);
    expect(f.cache.activeLeases, handles);
    expect(f.cache.estimatedRetainedBytes, greaterThan(bytes));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(f.cache.activeLeases, 0);
    f.cache.clearUnpinned();
    expect(f.cache.estimatedRetainedBytes, 0);
    expect(f.cache.preparedPictureCount, 0);
  });

  for (final (allocated, cold) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    testWidgets(
      'mixed text keeps its mounted source (allocated: $allocated, cold: $cold)',
      (tester) async {
        final opening = allocated
            ? '<p style="white-space:pre-wrap;line-height:.25">'
            : '<p>';
        final f = _Fixture(
          '$opening<span style="background:#ff0000;color:transparent">'
          'AB<b style="color:#0022ff;text-decoration:underline">C</b>D'
          '</span>${allocated ? '\n' : ' '}<ruby><rb>EF</rb><rt>xy</rt></ruby>'
          '${allocated ? '\nGG\nHH' : ''}</p>',
          height: 70,
        );
        f.drain();
        final snapshot = f.session.snapshot;
        final fragments = f.prepare(0);
        final inline = fragments
            .whereType<ForumBodyPreparedInlineFragment>()
            .single;
        final view = inline.view;
        final start = view.coverageStartUtf16;
        final end = view.coverageEndUtf16;
        final boxes = view.selectionBoxes(start, end);
        expect(boxes, isNotEmpty);
        expect(
          inline.nativeLeases.whereType<ForumBodyTextPictureLease>(),
          allocated ? isNotEmpty : isEmpty,
        );
        final surface = ForumBodyTextPageSurface.prepared(
          snapshot: snapshot,
          pageIndex: 0,
          layoutId: snapshot.layoutId,
          fragments: fragments,
        );
        final key = GlobalKey();
        final body = RepaintBoundary(key: key, child: surface);
        Future<Uint8List> show({Color? color, double radius = 0}) async {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.topLeft,
                child: ForumBodyTextBackgroundStyle(
                  color: color,
                  borderRadius: radius,
                  child: body,
                ),
              ),
            ),
          );
          return _pagePixels(tester, key);
        }

        final authored = await show();
        final red = _rgbCount(authored, 0xff0000);
        final ink = _rgbCount(authored, 0x0022ff);
        expect(red, greaterThan(0));
        expect(ink, greaterThan(0));
        if (cold) f.cache.clearUnpinned();
        final handles = f.cache.activeLeases;
        final element = tester.element(find.byWidget(surface));
        final square = await show(color: const Color(0xff00ff00));
        expect(_rgbCount(square, 0xff0000), 0);
        expect(_rgbCount(square, 0x00ff00), red);
        expect(_rgbCount(square, 0x0022ff), ink);
        final layouts = f.cache.layoutBuildCount;
        final pictures = f.cache.pictureBuildCount;
        final rounded = await show(color: const Color(0xff00ff00), radius: 4);
        expect(_rgbCount(rounded, 0x00ff00), inExclusiveRange(0, red));
        expect(_rgbCount(rounded, 0x0022ff), ink);
        expect(await show(), orderedEquals(authored));
        expect(tester.element(find.byWidget(surface)), same(element));
        expect(view.selectionBoxes(start, end), boxes);
        expect(f.cache.layoutBuildCount, layouts);
        expect(f.cache.pictureBuildCount, pictures);
        expect(f.cache.activeLeases, handles + (allocated ? 1 : 0));
        await tester.pumpWidget(const SizedBox.shrink());
        expect(f.cache.activeLeases, 0);
        f.cache.clearUnpinned();
        expect(f.cache.estimatedRetainedBytes, 0);
        expect(f.cache.preparedPictureCount, 0);
      },
    );
  }

  testWidgets('paragraph rounds natural ends across columns and pages', (
    tester,
  ) async {
    final f = _Fixture(
      '<p><span style="background-color:rgba(255,0,0,.5);color:transparent">'
      '${'A' * 24}</span></p>',
      height: 20,
      columns: const ForumBodyPageColumns(count: 2, gap: 20),
    );
    f.drain();
    final snapshot = f.session.snapshot;
    expect(snapshot, hasLength(2));
    expect(snapshot.first.fragments, hasLength(2));
    expect(snapshot.last.fragments, hasLength(1));
    final key = GlobalKey();
    Future<Uint8List> show(int index) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: ForumBodyTextBackgroundStyle(
                borderRadius: 9,
                child: ForumBodyTextPageSurface.prepared(
                  snapshot: snapshot,
                  pageIndex: index,
                  layoutId: snapshot.layoutId,
                  fragments: f.prepare(index),
                ),
              ),
            ),
          ),
        ),
      );
      return _pagePixels(tester, key);
    }

    int alpha(Uint8List pixels, int x, int y) => pixels[4 * (y * 100 + x) + 3];
    final first = await show(0);
    final work = f.cache.layoutBuildCount;
    expect(alpha(first, 1, 0), 0); // Natural beginning.
    expect(alpha(first, 1, 19), 128);
    expect(alpha(first, 61, 0), 128); // The same fill continues in column two.
    expect(alpha(first, 61, 19), 128);
    expect(alpha(first, 50, 8), 0); // Gutter.
    final second = await show(1);
    expect(alpha(second, 1, 0), 128); // The same fill continues on page two.
    expect(alpha(second, 1, 19), 0); // Natural ending.
    expect(f.cache.layoutBuildCount, work);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(f.cache.activeLeases, 0);
  });

  testWidgets(
    'single-level ruby and mixed text retain their contours across cuts',
    (tester) async {
      final plain =
          '<span style="background:rgba(255,0,0,.5)">'
          '${'A' * 20}</span>';
      const base = '<rb style="background:rgba(0,0,255,.5)">BC</rb>';
      const rt = '<rt style="background:rgba(255,255,0,.5)">xy</rt>';
      final html =
          '<p style="color:transparent">$plain '
          '<ruby style="background:rgba(0,255,0,.5)">$base$base$base$base$base$base'
          '$rt$rt$rt$rt$rt$rt</ruby></p>';
      final continuous = _Fixture(html, width: 40, height: 200)..drain();
      final sliced = _Fixture(
        html,
        height: 20,
        columns: const ForumBodyPageColumns(count: 2, gap: 20),
      )..drain();
      expect(continuous.session.snapshot, hasLength(1));
      expect(sliced.session.snapshot.length, greaterThan(2));
      final key = GlobalKey();
      Future<Uint8List> show(
        _Fixture fixture,
        int page,
        List<ForumBodyPreparedTextFragment> fragments,
      ) async {
        final snapshot = fixture.session.snapshot;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: ForumBodyTextBackgroundStyle(
                  borderRadius: 5,
                  child: ForumBodyTextPageSurface.prepared(
                    key: ObjectKey(fragments),
                    snapshot: snapshot,
                    pageIndex: page,
                    layoutId: snapshot.layoutId,
                    fragments: fragments,
                  ),
                ),
              ),
            ),
          ),
        );
        return _pagePixels(tester, key);
      }

      final uncut = continuous.prepare(0);
      final referenceView =
          (uncut.single as ForumBodyPreparedInlineFragment).view;
      final text = referenceView.content.projection.display.text;
      final reference = await show(continuous, 0, uncut);
      expect(_rgbCount(reference, 0x004080), greaterThan(0)); // RB over ruby.
      expect(_rgbCount(reference, 0x808000), greaterThan(0)); // RT.
      final copied = StringBuffer();
      var previousEnd = 0;
      var referenceY = 0;
      var rubyWindows = 0;
      final snapshot = sliced.session.snapshot;
      for (var page = 0; page < snapshot.length; page++) {
        final fragments = sliced.prepare(page);
        final pixels = await show(sliced, page, fragments);
        int alpha(int x, int y) => pixels[4 * (y * 100 + x) + 3];
        if (page == 0) {
          expect(alpha(1, 0), 0);
          expect(alpha(1, 19), 128);
          expect(alpha(61, 0), 128);
          expect(alpha(61, 19), 128);
        } else if (page == 1) {
          expect(alpha(1, 0), 128);
        }
        for (final (index, box) in snapshot[page].fragments.indexed) {
          final view =
              (fragments[index] as ForumBodyPreparedInlineFragment).view;
          final start = view.coverageStartUtf16;
          final end = view.coverageEndUtf16;
          expect(start, previousEnd);
          copied.write(
            view.content.projection.display.text.substring(start, end),
          );
          previousEnd = end;
          if (view.containerBackgrounds.isNotEmpty) rubyWindows++;
          expect(view.selectionBoxes(start, end), isNotEmpty);
          expect(box.height, box.height.round());
          for (var y = 0; y < box.height; y++) {
            final position =
                4 * ((box.top.round() + y) * 100 + box.left.round());
            final expected = 4 * ((referenceY + y) * 40);
            // Isolated rounded rectangles and equivalent contour paths can
            // rasterize antialiased edges a few channel values apart.
            for (var channel = 0; channel < 160; channel++) {
              final delta =
                  (pixels[position + channel] - reference[expected + channel])
                      .abs();
              if (delta > 16) {
                fail(
                  'Page $page, column at ${box.left}, row $y, '
                  'pixel ${channel ~/ 4} differs by $delta',
                );
              }
            }
          }
          referenceY += box.height.round();
        }
        for (var y = 0; y < 20; y++) {
          expect(alpha(50, y), 0);
        }
      }
      expect(copied.toString(), text);
      expect(rubyWindows, greaterThan(1));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(continuous.cache.activeLeases, 0);
      expect(sliced.cache.activeLeases, 0);
    },
  );

  test(
    'block slices exclude outer margins and repeat neither end padding nor text',
    () {
      final f = _Fixture(
        '<p>before</p><div style="margin:8px 0 9px;padding:2px 3px;background:red">a<br>b<br>c<br>d</div><p>after</p>',
      );
      f.drain(pages: 1);
      final prefix = f.session.snapshot;
      final first = prefix.single.backgrounds.single;
      expect(_rect(first), const Rect.fromLTWH(0, 18, 100, 12));
      f.drain();
      final pages = f.session.snapshot;
      expect(pages, hasLength(3));
      expect(pages.map((page) => _rect(page.backgrounds.single)), [
        const Rect.fromLTWH(0, 18, 100, 12),
        const Rect.fromLTWH(0, 0, 100, 30),
        const Rect.fromLTWH(0, 0, 100, 2),
      ]);
      expect(pages.last.fragments.single.top, 11);
      expect(prefix, hasLength(1));
      expect(_rect(first), const Rect.fromLTWH(0, 18, 100, 12));
      expect(() => prefix.single.backgrounds.clear(), throwsUnsupportedError);
      expect(
        pages
            .expand((page) => page.fragments)
            .map((fragment) => fragment.paragraphIndex),
        [0, 1, 2, 3, 4, 5],
      );
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'collapsed child margins stay outside background; negative end margin uses actual box end',
    () {
      final collapsed = _Fixture(
        '<p>before</p><div style="background:red;margin:3px"><p style="margin:8px 0 9px">a</p></div><p>after</p>',
        height: 100,
      );
      collapsed.drain();
      expect(
        _rect(collapsed.session.snapshot.single.backgrounds.single),
        const Rect.fromLTWH(3, 18, 94, 10),
      );
      expect(collapsed.session.snapshot.single.fragments.last.top, 37);
      final negative = _Fixture(
        '<div style="background:red;padding:2px"><p style="margin:0 0 -5px">a</p></div>',
      );
      negative.drain();
      final page = negative.session.snapshot.single;
      expect(_rect(page.backgrounds.single), const Rect.fromLTWH(0, 0, 100, 9));
      expect(
        page.usedHeight,
        12,
      ); // Actual glyph extent is not the auto box height.
    },
  );

  test('padding-only and rule boxes need no native font or source fragment', () {
    final padding = _Fixture(
      '<div style="background:red;padding-top:45px;padding-bottom:2px"></div>',
      height: 20,
    );
    padding.drain();
    expect(padding.session.snapshot.map((p) => p.backgrounds.single.height), [
      20,
      20,
      7,
    ]);
    expect(
      padding.session.snapshot.every(
        (p) => p.fragments.isEmpty && p.itemCount == 1,
      ),
      isTrue,
    );
    expect(padding.cache.layoutBuildCount, 0);
    final rule = _Fixture(
      '<div style="background:red"><hr style="margin:0"></div>',
    );
    rule.drain();
    final page = rule.session.snapshot.single;
    expect(page.backgrounds.single.height, 1);
    expect(page.rules, hasLength(1));
    expect(page.fragments, isEmpty);
    expect(page.itemCount, 2);
    expect(rule.cache.layoutBuildCount, 0);
  });

  test(
    'an untouched box moves with its first indivisible content, leaving no false first-page fill',
    () {
      final f = _Fixture(
        '<p>first</p><div style="background:red"><p style="font-size:20px">x</p></div>',
        height: 25,
      );
      f.drain();
      expect(f.session.snapshot, hasLength(2));
      expect(f.session.snapshot.first.backgrounds, isEmpty);
      expect(f.session.snapshot.last.backgrounds.single.height, 20);
    },
  );

  test(
    'empty, transparent and hidden boxes add no decoration or fabricated text',
    () {
      for (final html in [
        '<div style="background:red"></div>',
        '<div style="background:transparent;padding-top:3px"></div>',
        '<div style="background:red;visibility:hidden;padding-top:3px"></div>',
      ]) {
        final f = _Fixture(html);
        f.drain();
        expect(f.session.snapshot.expand((p) => p.backgrounds), isEmpty);
        expect(f.session.snapshot.expand((p) => p.fragments), isEmpty);
        expect(f.cache.layoutBuildCount, 0);
      }
    },
  );

  test(
    'background metadata cannot bypass the fragment budget or mutate a failed published prefix',
    () {
      final f = _Fixture(
        '<div style="background:red;padding-top:45px"></div>',
        height: 20,
        fragments: 2,
      );
      f.drain(pages: 2);
      final prefix = f.session.snapshot;
      expect(
        () => f.drain(),
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageFailure.fragmentLimit,
          ),
        ),
      );
      expect(f.session.state, ForumBodyTextPageSessionState.failed);
      expect(f.session.snapshot, hasLength(2));
      expect(prefix.every((p) => p.backgrounds.single.height == 20), isTrue);
      expect(f.cache.activeLeases, 0);
      final text = _Fixture(
        '<div style="background:red">a</div>',
        fragments: 1,
      );
      expect(
        () => text.drain(),
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageFailure.fragmentLimit,
          ),
        ),
      );
      expect(text.session.snapshot, isEmpty);
      expect(text.cache.activeLeases, 0);
    },
  );

  test(
    'open background depth is bounded independently of native fonts and parser configuration',
    () {
      final f = _Fixture('');
      final composer = ForumBodyTextPageComposer(
        identity: f.document.identity,
        layoutId: 'depth',
        width: 100,
        height: 20,
        maxPages: 1,
        maxFragments: 1000,
      );
      addTearDown(composer.close);
      for (var i = 0; i < 128; i++) {
        composer.openBackground(
          path: '$i',
          left: 0,
          width: 100,
          color: const Color(0xffff0000),
        );
      }
      expect(
        () => composer.openBackground(
          path: 'overflow',
          left: 0,
          width: 100,
          color: const Color(0xffff0000),
        ),
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageFailure.backgroundDepth,
          ),
        ),
      );
      composer.close();
      expect(composer.retainedFragmentCount, 0);
      expect(f.cache.layoutBuildCount, 0);
    },
  );

  test(
    'closing during a continued paragraph retires draft decoration and native input, preserving the published prefix',
    () {
      final f = _Fixture(
        '<div style="background:red"><p>${List.filled(100, 'a ').join()}</p></div>',
      );
      f.drain(pages: 1);
      final prefix = f.session.snapshot;
      expect(f.cache.activeLeases, 1);
      expect(prefix.single.backgrounds.single.height, 30);
      f.session.close();
      expect(f.cache.activeLeases, 0);
      expect(f.session.retainedParagraphCount, 0);
      expect(prefix.single.backgrounds.single.height, 30);
      expect(
        () => f.session.advance(maxEvents: 1, maxLines: 1),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'actual Page surface paints nested translucent border boxes, excludes margins and receives no source taps',
    (tester) async {
      final f = _Fixture(
        '<div style="background:red;margin:0 5px;padding:2px"><div style="background:rgba(0,0,255,.5);width:40px;padding-top:6px"></div></div>',
        height: 20,
      );
      f.drain();
      final snapshot = f.session.snapshot;
      expect(snapshot.single.backgrounds.map((b) => b.path), ['0', '0/0']);
      final key = GlobalKey();
      var taps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: ForumBodyTextPageSurface(
                snapshot: snapshot,
                pageIndex: 0,
                layoutId: snapshot.layoutId,
                leases: [],
                onSourceTap: (_, _) => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(8, 4));
      expect(taps, 0);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(5, 0, 90, 10),
        Paint()..color = const Color(0xffff0000),
      );
      canvas.drawRect(
        const Rect.fromLTWH(7, 2, 40, 6),
        Paint()..color = const Color(0x800000ff),
      );
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final reference = await picture.toImage(100, 20);
        final actual = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage(pixelRatio: 1);
        try {
          expect(
            (await actual.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List(),
            orderedEquals(
              (await reference.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List(),
            ),
          );
        } finally {
          actual.dispose();
          reference.dispose();
          picture.dispose();
        }
      });
      expect(f.cache.layoutBuildCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
