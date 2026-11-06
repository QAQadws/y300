import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_text_page_preparation.dart'
    show createForumBodyTextPagePreparation;
import '../inline/test_support/mixed_emphasis_parent_fixture.dart';

const _html =
    '<p style="white-space:pre-wrap;line-height:.25"><span style="color:red">AA</span>\nCC<ruby>B<rt>b</rt></ruby>\n<span style="color:green">DD</span>\n<span style="color:blue">EE</span></p>';

final class _Fixture {
  _Fixture({
    String html = _html,
    TextDirection direction = TextDirection.ltr,
    double width = 300,
    double height = 35,
    int entries = 128,
    int bytes = 1 << 26,
    int handles = 128,
    double fontSize = 20,
    int? maxEntriesPerPage,
  }) {
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: bytes,
    );
    session = ForumBodyTextPageSession(
      document: const ForumBodyParser().parse(
        html: html,
        sourceId: 'mixed-font-pages',
        conversionIdentity: 'none',
      ),
      reader: ForumBodyReaderStyle(
        textStyle: TextStyle(
          fontFamily: 'Ahem',
          fontSize: fontSize,
          color: Color(0xff123456),
        ),
        fontRevision: 'mixed-font-pages',
        linkColor: const Color(0xff0000ff),
        textDirection: direction,
        paragraphBefore: 0,
        paragraphAfter: 0,
      ),
      cache: cache,
      limits: ForumBodyTextPageSessionLimits(
        maxPages: 200,
        maxFragments: 1000,
        maxParagraphs: 100,
        maxTextCodeUnits: 100000,
        maxRuns: 10000,
        maxIssuedLeases: handles,
      ),
      layoutId: 'mixed-font-pages',
      width: width,
      height: height,
      maxNativeEntriesPerPage: maxEntriesPerPage,
    );
    addTearDown(close);
  }
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  void finish() {
    for (var n = 0; !session.isComplete && n < 50000; n++) {
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final step = session.advance(
        maxEvents: 1,
        maxLines: 1,
        maxFormatParts: 1,
      );
      expect(step.formatUnitsPrepared, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(cache.layoutBuildCount - before.$1, lessThanOrEqualTo(1));
      expect(cache.pictureBuildCount, before.$2);
    }
    expect(session.isComplete, isTrue);
  }

  List<ForumBodyPreparedTextFragment> prepare(int page) {
    final job = session.openPagePreparation(page);
    try {
      for (var n = 0; !job.isReady && n < 50000; n++) {
        final before = cache.layoutBuildCount + cache.pictureBuildCount;
        final step = job.advance(maxFragments: 1, maxParts: 1);
        expect(step.waitingForLayoutBudget, isFalse);
        expect(
          cache.layoutBuildCount + cache.pictureBuildCount - before,
          lessThanOrEqualTo(1),
        );
      }
      expect(job.isReady, isTrue);
      return job.takeFragments();
    } finally {
      job.close();
    }
  }

  void close() {
    session.close();
    cache.close();
  }
}

Future<Map<int, int>> _pixels(ForumBodyInlineParagraphView view) async {
  final recorder = ui.PictureRecorder();
  view.paint(Canvas(recorder), Offset.zero);
  final drawing = recorder.endRecording(),
      image = await drawing.toImage(view.width.ceil(), view.height.ceil());
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final colors = <int, int>{};
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i + 3) != 0) {
        colors.update(bytes.getUint32(i), (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return colors;
  } finally {
    image.dispose();
    drawing.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    test(
      'actual page session delivers complete mixed glyphs after eviction $direction',
      () async {
        final fixture = _Fixture(direction: direction)..finish();
        expect(fixture.session.snapshot.length, 4);
        final expected = [
          {0xff0000ff: 800},
          {0x123456ff: 1300},
          {0x008000ff: 800},
          {0x0000ffff: 800},
        ];
        final copied = StringBuffer();
        for (var page = 0; page < 4; page++) {
          fixture.cache.clearUnpinned();
          expect(fixture.cache.activeLeases, 0);
          final bindings = fixture.prepare(page);
          expect(bindings, hasLength(1));
          final binding = bindings.single as ForumBodyPreparedInlineFragment;
          try {
            final view = binding.view,
                fragment = fixture.session.snapshot[page].fragments.single;
            expect(view.height, fragment.height);
            expect(view.nativeLeases, hasLength(page == 1 ? 5 : 3));
            expect(await _pixels(view), expected[page]);
            copied.write(
              binding.projection.text.substring(
                fragment.coverageStartUtf16,
                fragment.coverageEndUtf16,
              ),
            );
            for (final context in view.content.contexts) {
              final start = context.startUtf16.clamp(
                    view.coverageStartUtf16,
                    view.coverageEndUtf16,
                  ),
                  end = context.endUtf16.clamp(
                    view.coverageStartUtf16,
                    view.coverageEndUtf16,
                  );
              if (start >= end) continue;
              for (final g in binding.projection.graphemeRanges(
                startUtf16: start,
                endUtf16: end,
              )) {
                for (final box in binding.glyphBoxes(
                  g.startUtf16,
                  g.endUtf16,
                )) {
                  if (box.toRect().isEmpty) continue;
                  expect(box.top, greaterThanOrEqualTo(-1e-3));
                  expect(box.bottom, lessThanOrEqualTo(fragment.height + 1e-3));
                  final hit = view.sourceHitAt(box.toRect().center);
                  expect(hit.window, same(context));
                  expect(hit.position.isExact, isTrue);
                }
              }
            }
          } finally {
            binding.close();
          }
          expect(fixture.session.activeIssuedLeases, 0);
          expect(fixture.cache.activeLeases, 0);
        }
        expect(copied.toString(), 'AA\nCCBb\nDD\nEE');
      },
    );
  }
  test('fitting normal mixed body retains the original native parent path', () {
    final fixture = _Fixture(
      html: '<p style="line-height:1.6">AA<ruby>B<rt>b</rt></ruby>CC</p>',
      height: 100,
    )..finish();
    final values = fixture.prepare(0);
    try {
      expect(values.single.nativeLeases, hasLength(3));
    } finally {
      for (final v in values) {
        v.close();
      }
    }
    expect(fixture.cache.activeLeases, 0);
  });

  test('tight font frames reuse the measured split of an overwide word', () {
    final fixture = _Fixture(
      html:
          '<p style="white-space:pre-wrap;line-height:.25">'
          'AA\nABC<sup>2</sup>DE\n<ruby>B<rt>b</rt></ruby>\nCC</p>',
      width: 65,
      height: 200,
    )..finish();
    fixture.cache.clearUnpinned();
    final bindings = fixture.prepare(0);
    try {
      final binding = bindings.single as ForumBodyPreparedInlineFragment;
      expect(
        binding.view.nativeLeases.whereType<ForumBodyTextPictureLease>(),
        isNotEmpty,
      );
      expect(binding.projection.text, 'AA\nABC2DE\nBb\nCC');
      final superscript = binding.view.content.contexts.singleWhere(
        (window) => window.content.projection.text == '2',
      );
      final box = binding
          .glyphBoxes(superscript.startUtf16, superscript.endUtf16)
          .single;
      final hit = binding.view.sourceHitAt(box.toRect().center);
      expect(hit.window, same(superscript));
      expect(hit.position.isExact, isTrue);
    } finally {
      for (final binding in bindings) {
        binding.close();
      }
    }
    expect(fixture.cache.activeLeases, 0);
  });

  const twoBodies =
      '<p style="white-space:pre-wrap;line-height:.25">AA\nCC<ruby>B<rt>b</rt></ruby></p><p style="white-space:pre-wrap;line-height:.25">DD\nEE<ruby>B<rt>b</rt></ruby></p>';
  test(
    'entry-bound composition seals before a second allocated parent scene',
    () {
      final fixture = _Fixture(
        html: twoBodies,
        entries: 8,
        height: 200,
        maxEntriesPerPage: 8,
      )..finish();
      expect(fixture.session.snapshot.length, 2);
      for (var page = 0; page < 2; page++) {
        final fragments = fixture.prepare(page);
        try {
          expect(fragments, hasLength(1));
          expect(
            fragments.single.nativeLeases
                .whereType<ForumBodyTextPictureLease>(),
            hasLength(1),
          );
        } finally {
          for (final f in fragments) {
            f.close();
          }
        }
      }
      expect(fixture.cache.activeLeases, 0);
    },
  );
  test(
    'an unbounded over-capacity page fails aggregate preflight without native work',
    () {
      final fixture = _Fixture(html: twoBodies, entries: 8, height: 200)
        ..finish();
      expect(fixture.session.snapshot.length, 1);
      final before = (
        fixture.cache.layoutBuildCount,
        fixture.cache.pictureBuildCount,
      );
      expect(
        () => fixture.prepare(0),
        throwsA(
          isA<ForumBodyTextPagePreparationException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPagePreparationFailure.intrinsicBudget,
          ),
        ),
      );
      expect((
        fixture.cache.layoutBuildCount,
        fixture.cache.pictureBuildCount,
      ), before);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.session.activeIssuedLeases, 0);
    },
  );
  test(
    'late pages in a tall mixed source rebase native rows into the page',
    () async {
      final fixture = _Fixture(
        html:
            '<p style="white-space:pre-wrap;line-height:.25">${List.filled(600, 'A\n').join()}<ruby>B<rt>b</rt></ruby></p>',
        fontSize: 64,
        height: 1000,
      )..finish();
      final page = fixture.session.snapshot.length - 1,
          meta = fixture.session.snapshot[page].fragments.single;
      expect(meta.startLine * 64, greaterThan(32768));
      fixture.cache.clearUnpinned();
      final fragments = fixture.prepare(page);
      final body = fragments.single as ForumBodyPreparedInlineFragment;
      try {
        expect(
          body.view.nativeLeases.whereType<ForumBodyTextPictureLease>(),
          isEmpty,
        );
        expect(await _pixels(body.view), isNotEmpty);
        for (final g in body.projection.graphemeRanges(
          startUtf16: meta.coverageStartUtf16,
          endUtf16: meta.coverageEndUtf16,
        )) {
          for (final box in body.glyphBoxes(g.startUtf16, g.endUtf16)) {
            if (box.toRect().isEmpty) continue;
            expect(box.top, greaterThanOrEqualTo(-.01));
            expect(box.bottom, lessThanOrEqualTo(meta.height + .01));
            expect(body.view.sourceAt(box.toRect().center).isExact, isTrue);
          }
        }
      } finally {
        body.close();
      }
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'cancelling every native-yield quantum retires source admission resources',
    () {
      var completed = false;
      for (var stop = 0; stop < 2000; stop++) {
        final fixture = _Fixture();
        for (var n = 0; n < stop && !fixture.session.isComplete; n++) {
          fixture.session.advance(
            maxEvents: 1,
            maxLines: 1,
            maxFormatParts: 32,
          );
        }
        completed = fixture.session.isComplete;
        fixture.close();
        expect(fixture.cache.activeLeases, 0);
        expect(fixture.cache.estimatedRetainedBytes, 0);
        if (completed) break;
      }
      expect(completed, isTrue);
    },
  );

  test(
    'cancelling every cold page quantum releases measured and visible resources',
    () {
      final fixture = _Fixture()..finish();
      var completed = false;
      for (var stop = 0; stop < 2000; stop++) {
        fixture.cache.clearUnpinned();
        final job = fixture.session.openPagePreparation(1);
        for (var n = 0; n < stop && !job.isReady; n++) {
          job.advance(maxFragments: 1, maxParts: 32);
        }
        completed = job.isReady;
        job.close();
        expect(fixture.cache.activeLeases, 0);
        expect(fixture.session.activeIssuedLeases, 0);
        if (completed) break;
      }
      expect(completed, isTrue);
    },
  );

  test(
    'a saved frame rejects different current font scaling after eviction',
    () {
      final source = MixedEmphasisParentFixture(
        '<ruby>B<rt>b</rt></ruby>',
        parentStyle: 'white-space:pre-wrap;line-height:.25',
        prefix: 'AA\nCC',
        suffix: '\nDD',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 128,
        maxEstimatedBytes: 1 << 26,
      );
      addTearDown(cache.close);
      final measuring = ForumBodyInlineFontFramePreparation(
        input: source.input,
        cache: cache,
        textScaler: TextScaler.noScaling,
        ensureOwner: () {},
      );
      while (!measuring.isReady) {
        measuring.advance(maxParts: 32);
      }
      final measured = measuring.takeMeasurement(), plan = measured.plan;
      final natural = plan.allocation.input.natural.parentRequest.acquire(
        cache,
        width: plan.width,
        textScaler: plan.textScaler,
        cachedOnly: true,
      )!;
      measured.close();
      final input = ForumBodyInlinePageContent.withFontFrames(plan);
      final composer = ForumBodyTextPageComposer(
        identity: input.identity,
        layoutId: 'saved-frame-scale',
        width: plan.width,
        height: 200,
        maxPages: 10,
        maxFragments: 10,
      );
      addTearDown(composer.close);
      composer.appendInline(
        lease: natural,
        fontFrames: plan,
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
      );
      while (!composer.needsInput) {
        composer.advance(maxLines: 32);
      }
      composer.finish();
      cache.clearUnpinned();
      expect(cache.entryCount, 0);
      var retired = false;
      final job = createForumBodyTextPagePreparation(
        cache: cache,
        snapshot: composer.snapshot,
        pageIndex: 0,
        inputs: [input],
        textScaler: const TextScaler.linear(1.5),
        ensureOwner: () {},
        onTransfer: (_, _) {
          fail('stale input transferred');
        },
        onRetire: (_) {
          retired = true;
        },
      );
      addTearDown(job.close);
      expect(
        () {
          for (var n = 0; !job.isReady && n < 20000; n++) {
            job.advance(maxFragments: 1, maxParts: 32);
          }
        },
        throwsA(
          isA<ForumBodyTextPageSurfaceException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageSurfaceFailure.geometry,
          ),
        ),
      );
      expect(retired, isTrue);
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
    },
  );
}
