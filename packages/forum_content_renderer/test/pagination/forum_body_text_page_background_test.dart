import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Fixture {
  _Fixture(String html, {double height = 30, int fragments = 100}) {
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
      width: 100,
      height: height,
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
}

Rect _rect(ForumBodyTextPageBackground box) =>
    Rect.fromLTWH(box.left, box.top, box.width, box.height);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ruby background overrides reuse the mounted native page', (
    tester,
  ) async {
    final f = _Fixture(
      '<p><ruby style="background-color:#ff0000;color:transparent;font-size:20px">'
      '<rb>AB</rb><rt>a</rt></ruby> plain</p>',
      height: 70,
    );
    f.drain();
    final snapshot = f.session.snapshot;
    final job = f.session.openPagePreparation(0);
    final List<ForumBodyPreparedTextFragment> fragments;
    try {
      for (var i = 0; !job.isReady && i < 1000; i++) {
        job.advance(maxFragments: 1, maxParts: 1);
      }
      expect(job.isReady, isTrue);
      fragments = job.takeFragments();
    } finally {
      job.close();
    }
    final inline = fragments
        .whereType<ForumBodyPreparedInlineFragment>()
        .single;
    expect(inline.view.containerBackgrounds, hasLength(1));
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
      return (await tester.runAsync(() async {
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
    }

    int colored(Uint8List pixels, int channel) {
      var count = 0;
      for (var index = 0; index < pixels.length; index += 4) {
        if (pixels[index + channel] == 255 &&
            pixels[index + (1 - channel)] == 0) {
          count++;
        }
      }
      return count;
    }

    final authored = await show();
    final element = tester.element(find.byWidget(surface));
    final work = (
      f.cache.layoutBuildCount,
      f.cache.pictureBuildCount,
      f.cache.activeLeases,
    );
    expect(colored(authored, 0), greaterThan(0));
    expect(colored(authored, 1), 0);
    const green = Color(0xff00ff00);
    final square = await show(color: green);
    final rounded = await show(color: green, radius: 9);
    expect(colored(square, 0), 0);
    expect(colored(rounded, 1), greaterThan(0));
    expect(colored(rounded, 1), lessThan(colored(square, 1)));
    expect(await show(), orderedEquals(authored));
    expect(tester.element(find.byWidget(surface)), same(element));
    expect((
      f.cache.layoutBuildCount,
      f.cache.pictureBuildCount,
      f.cache.activeLeases,
    ), work);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(f.cache.activeLeases, 0);
  });

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
