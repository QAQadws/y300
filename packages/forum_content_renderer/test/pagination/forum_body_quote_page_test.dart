import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _theme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xffffffff),
  foreground: Color(0xff000000),
  link: Color(0xff0000ff),
  quoteSurface: Color(0xffffeedd),
  quoteForeground: Color(0xff556677),
  codeSurface: Color(0xffdddddd),
  codeForeground: Color(0xff000000),
);

ForumBodyReaderStyle _reader([ForumBodyStylePolicy? policy]) =>
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontSize: 10,
        height: 1,
        fontFamily: 'Ahem',
        color: Color(0xff000000),
      ),
      fontRevision: 'ahem',
      linkColor: _theme.link,
      paragraphAfter: 0,
      theme: _theme,
      policy: policy,
    );

final class _Fixture {
  _Fixture(String html, {double height = 100, ForumBodyStylePolicy? policy}) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'quote',
      conversionIdentity: 'none',
    );
    styles = const ForumBodyStyleResolver().resolve(document, _reader(policy));
    cache = ForumBodyParagraphCache(maxEntries: 16, maxEstimatedBytes: 1 << 22);
    session = ForumBodyTextPageSession(
      document: document,
      reader: _reader(policy),
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 500,
        maxParagraphs: 100,
        maxTextCodeUnits: 20000,
        maxRuns: 1000,
        maxIssuedLeases: 64,
      ),
      layoutId: 'quote-page',
      width: 100,
      height: height,
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
  }
  late final ForumBodyDocument document;
  late final ForumBodyStyleResult styles;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  void drain({int? pages}) {
    var calls = 0;
    while (!session.isComplete &&
        (pages == null || session.snapshot.length < pages)) {
      if (++calls > 10000) fail('Quote session did not finish');
      final step = session.advance(maxEvents: 1, maxLines: 1);
      expect(step.madeProgress, isTrue);
      expect(step.pagesPublished, lessThanOrEqualTo(1));
      expect(step.flowWorkDone, lessThanOrEqualTo(1));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('packages/forum_content_renderer/ForumBodyInlineSpace')
          ..addFont(
            rootBundle.load(
              'packages/forum_content_renderer/assets/fonts/inline_space.ttf',
            ),
          ))
        .load();
  });

  test(
    'Discuz quote wrapper owns inner blockquote through intervening blocks without double chrome',
    () {
      final f = _Fixture(
        '<div class="quote"><div><blockquote><b>a</b> b</blockquote></div></div><p>c</p>',
      );
      f.drain();
      final page = f.session.snapshot.single;
      expect(page.backgrounds, hasLength(1));
      expect(page.backgrounds.single.path, '0');
      expect(page.backgrounds.single.color, _theme.quoteSurface);
      expect(page.backgrounds.single.quoteDecoration!.borderColor, _theme.link);
      final quote = page.fragments.first, ordinary = page.fragments.last;
      expect((quote.left, quote.width, quote.top), (13.0, 77.0, 8.0));
      expect(ordinary.left, 0);
      expect(f.styles.byPath['0/0/0']!.quoteDecoration, isNull);
      expect(f.styles.byPath['0/0/0/0']!.textStyle.fontWeight, FontWeight.w700);
      expect(f.styles.byPath['0/0/0']!.textStyle.color, _theme.quoteForeground);
      expect(f.styles.byPath['1']!.textStyle.color, const Color(0xff000000));
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'standalone nested quotes retain independent actual boxes and roles',
    () {
      final f = _Fixture(
        '<blockquote>a<blockquote>b</blockquote>c</blockquote>',
      );
      f.drain();
      expect(f.session.snapshot.single.backgrounds.map((box) => box.path), [
        '0',
        '0/1',
      ]);
      expect(
        f.session.snapshot.single.fragments.map(
          (part) => (part.left, part.width),
        ),
        [(13.0, 77.0), (26.0, 54.0), (13.0, 77.0)],
      );
      expect(f.styles.byPath['0/1']!.quoteDecoration, isNotNull);
    },
  );

  test(
    'quote author colors survive body-only policy; all-text policy restores semantic surface',
    () {
      const html =
          '<blockquote style="color:red;background:green"><span>a</span></blockquote>';
      final body = _Fixture(
        html,
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.foreground: ForumBodyStyleScope.forceBody,
          ForumBodyStyleProperty.background: ForumBodyStyleScope.forceBody,
        }),
      );
      body.drain();
      expect(
        body.styles.byPath['0/0']!.textStyle.color,
        const Color(0xffff0000),
      );
      expect(
        body.session.snapshot.single.backgrounds.single.color,
        const Color(0xff008000),
      );
      final all = _Fixture(
        html,
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.foreground: ForumBodyStyleScope.forceAll,
          ForumBodyStyleProperty.background: ForumBodyStyleScope.forceAll,
        }),
      );
      all.drain();
      expect(
        all.styles.byPath['0/0']!.textStyle.color,
        const Color(0xff000000),
      );
      expect(
        all.session.snapshot.single.backgrounds.single.color,
        _theme.quoteSurface,
      );
    },
  );

  test(
    'exact full page waits for actual quote close so both final corners are immutable',
    () {
      final f = _Fixture('<blockquote>a</blockquote>', height: 26);
      f.drain();
      expect(f.session.snapshot, hasLength(1));
      final box = f.session.snapshot.single.backgrounds.single;
      expect((box.height, box.startsBox, box.endsBox), (26.0, true, true));
      expect(f.session.snapshot.single.fragments.single.top, 8);
    },
  );

  test(
    'continued quotes keep the side edge without repeating padding or rounding each page',
    () {
      final f = _Fixture(
        '<blockquote>aa<br>bb<br>cc<br>dd<br>ee<br>ff<br>gg</blockquote>',
        height: 30,
      );
      f.drain(pages: 1);
      final prefix = f.session.snapshot;
      f.drain();
      final pages = f.session.snapshot;
      expect(pages, hasLength(3));
      expect(
        pages.map(
          (p) => (
            p.backgrounds.single.height,
            p.backgrounds.single.startsBox,
            p.backgrounds.single.endsBox,
          ),
        ),
        [(30.0, true, false), (30.0, false, false), (28.0, false, true)],
      );
      expect(pages.map((p) => p.fragments.first.top), [8, 0, 0]);
      expect(pages.expand((p) => p.fragments).map((p) => p.paragraphIndex), [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(prefix.single.backgrounds.single.endsBox, isFalse);
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'long quote padding progresses across full pages and does not invent source content',
    () {
      final f = _Fixture(
        '<blockquote style="padding-top:45px;padding-bottom:0"></blockquote>',
        height: 20,
      );
      f.drain();
      expect(f.session.snapshot.map((p) => p.backgrounds.single.height), [
        20,
        20,
        5,
      ]);
      expect(f.session.snapshot.every((p) => p.fragments.isEmpty), isTrue);
      expect(f.cache.layoutBuildCount, 0);
    },
  );

  test(
    'quote cancellation releases actual input while old rounded slices stay immutable',
    () {
      final f = _Fixture(
        '<blockquote><p>${List.filled(100, 'a ').join()}</p></blockquote>',
        height: 30,
      );
      f.drain(pages: 1);
      final prefix = f.session.snapshot;
      expect(f.cache.activeLeases, 1);
      expect(prefix.single.backgrounds.single.endsBox, isFalse);
      f.session.close();
      expect(f.cache.activeLeases, 0);
      expect(f.session.retainedParagraphCount, 0);
      expect(prefix.single.backgrounds.single.endsBox, isFalse);
    },
  );

  test(
    'single-level ruby inside quote uses real source windows, author styles and selected family',
    () {
      final f = _Fixture(
        '<div class="quote"><blockquote><ruby><rb><span style="font-size:12px;color:red">AB</span></rb><rt>cd</rt></ruby></blockquote></div>',
      );
      f.drain();
      final preparation = f.session.openPagePreparation(0);
      while (!preparation.isReady) {
        preparation.advance(maxFragments: 4);
      }
      final fragments = preparation.takeFragments();
      try {
        final view = (fragments.single as ForumBodyPreparedInlineFragment).view;
        expect(view.content.contexts.map((c) => c.content.style.role), [
          ForumBodyTextRole.quote,
          ForumBodyTextRole.ruby,
        ]);
        expect(
          view.content.contexts.every(
            (c) => c.content.style.textStyle.fontFamily == 'Ahem',
          ),
          isTrue,
        );
        for (final window in view.content.contexts) {
          final boxes = view.glyphBoxes(window.startUtf16, window.endUtf16);
          expect(boxes, isNotEmpty);
          for (final box in boxes) {
            final hit = view.sourceHitAt(box.toRect().center);
            expect(hit.position.isExact, isTrue);
            expect(hit.window, same(window));
          }
        }
        expect(f.session.snapshot.single.backgrounds, hasLength(1));
      } finally {
        for (final fragment in fragments) {
          fragment.close();
        }
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  for (final extent in [26, 46]) {
    testWidgets(
      'quote chrome pixels match one complete native box sliced across pages ($extent)',
      (tester) async {
        final height = extent == 26 ? 26.0 : 30.0;
        final f = _Fixture(
          '<blockquote style="padding-top:${extent - 8}px"></blockquote>',
          height: height,
        );
        f.drain();
        final referenceRecorder = ui.PictureRecorder();
        final referencePainter = BoxDecoration(
          color: _theme.quoteSurface,
          border: const Border(
            left: BorderSide(color: Color(0xff0000ff), width: 3),
          ),
          borderRadius: BorderRadius.circular(6),
        ).createBoxPainter();
        referencePainter.paint(
          Canvas(referenceRecorder),
          Offset.zero,
          ImageConfiguration(size: Size(100, extent * 1.0)),
        );
        final referencePicture = referenceRecorder.endRecording();
        try {
          for (final page in f.session.snapshot) {
            final key = GlobalKey();
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: key,
                    child: ForumBodyTextPageSurface(
                      snapshot: f.session.snapshot,
                      pageIndex: page.index,
                      layoutId: f.session.snapshot.layoutId,
                      leases: [],
                    ),
                  ),
                ),
              ),
            );
            await tester.runAsync(() async {
              final recorder = ui.PictureRecorder();
              final canvas = Canvas(recorder)
                ..translate(0, -page.index * height);
              canvas.drawPicture(referencePicture);
              final picture = recorder.endRecording();
              final expected = await picture.toImage(100, height.toInt());
              final actual = await tester
                  .renderObject<RenderRepaintBoundary>(find.byKey(key))
                  .toImage(pixelRatio: 1);
              try {
                expect(
                  (await actual.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!.buffer.asUint8List(),
                  orderedEquals(
                    (await expected.toByteData(
                      format: ui.ImageByteFormat.rawRgba,
                    ))!.buffer.asUint8List(),
                  ),
                );
              } finally {
                actual.dispose();
                expected.dispose();
                picture.dispose();
              }
            });
            expect(tester.takeException(), isNull);
          }
        } finally {
          referencePicture.dispose();
          referencePainter.dispose();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
