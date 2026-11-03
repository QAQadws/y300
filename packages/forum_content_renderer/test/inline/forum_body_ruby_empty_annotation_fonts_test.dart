import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_glyph_tree_fixture.dart';

final class _Sizes extends TextScaler {
  _Sizes({double small = 1.4, double large = 1.1})
    : state = _SizeState(small, large);
  final _SizeState state;
  double get small => state.small;
  set small(double value) => state.small = value;
  bool get forbid => state.forbid;
  set forbid(bool value) => state.forbid = value;
  @override
  double scale(double size) {
    if (forbid) throw StateError('Caller scaler retained by native font');
    return size * (size < 20 ? state.small : state.large);
  }

  @override
  double get textScaleFactor => throw StateError('Use actual font size');
}

// Mutable caller state deliberately tests that native painters retain samples.
final class _SizeState {
  _SizeState(this.small, this.large);
  double small, large;
  bool forbid = false;
}

ForumBodyRubyGlyphTreeBands _bands(
  String html,
  ForumBodyParagraphCache cache, {
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
}) => rubyGlyphTreeBandsFixture(
  html,
  cache,
  direction: direction,
  scaler: scaler,
  sourceId: 'empty-annotation-fonts',
  fontRevision: 'empty-font-ahem',
);

ForumBodyRubyEmptyAnnotationFonts _finish(
  ForumBodyRubyEmptyAnnotationFontsPreparation work, {
  bool cachedOnly = false,
  int quantum = 1,
}) {
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(10000));
      final step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.formatUnitsPrepared, inInclusiveRange(1, quantum));
      expect(step.layoutsBuilt, lessThanOrEqualTo(1));
      expect(step.picturesBuilt, 0);
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
    }
    expect(work.nativeLeases, isEmpty);
    return work.takeFonts();
  } finally {
    work.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(
    () => cache = ForumBodyParagraphCache(
      maxEntries: 64,
      maxEstimatedBytes: 1 << 24,
    ),
  );
  tearDown(() => cache.close());
  for (final style in [
    'font-size:10px;line-height:.2;text-emphasis:inherit',
    'font-size:32px;line-height:4;font-weight:700;font-style:italic;letter-spacing:2px',
    'font-size:12px;visibility:hidden;line-height:.4',
  ]) {
    for (final direction in TextDirection.values) {
      for (final nonlinear in [false, true]) {
        test(
          'real empty RT natural font $style $direction nonlinear=$nonlinear',
          () {
            final scaler = nonlinear ? _Sizes() : TextScaler.noScaling;
            final bands = _bands(
              '<ruby style="text-emphasis:circle"><rb>A</rb><rt style="$style"> \t </rt></ruby>',
              cache,
              direction: direction,
              scaler: scaler,
            );
            final before = bands.geometry.metrics.glyphHandleCount;
            final value = _finish(
              ForumBodyRubyEmptyAnnotationFontsPreparation(
                bands: bands,
                cache: cache,
                ensureOwner: () {},
                expectedTextScaler: scaler,
              ),
            );
            expect(value.fonts, hasLength(1));
            final font = value.fonts.single,
                source = bands.geometry.sources.last;
            expect(font.source, same(source));
            expect(value.bands, same(bands));
            expect(value.fontForSource(source.source.id), same(font));
            expect(
              value.fontForSource(bands.geometry.sources.first.source.id),
              isNull,
            );
            expect(source.source.needsNative, isFalse);
            expect(source.source.original.projection.text.trim(), isEmpty);
            expect(source.source.content.projection.text, isEmpty);
            expect(
              () => bands.geometry.metrics.input.requestForSource(
                source.source.id,
              ),
              throwsArgumentError,
            );
            final natural = source.source.content.style.textStyle.copyWith(
              height: kTextHeightNone,
            );
            expect(font.request.content.style.textStyle, natural);
            expect(font.request.content.style.textDirection, direction);
            expect(font.request.content.style.textEmphasis.isEnabled, isFalse);
            expect(font.request.content.isSourceFree, isTrue);
            expect(font.request.content.path, isNull);
            expect(font.request.content.projection.parts, isEmpty);
            expect(font.request.content.runs, isEmpty);
            final painter = TextPainter(
              text: TextSpan(text: '', style: natural),
              textDirection: direction,
              textScaler: scaler,
            )..layout();
            try {
              expect(
                font.bounds,
                Rect.fromLTWH(0, 0, painter.width, painter.height),
              );
              expect(
                font.alphabeticBaseline,
                painter.computeDistanceToActualBaseline(
                  TextBaseline.alphabetic,
                ),
              );
            } finally {
              painter.dispose();
            }
            expect(font.bounds.height, greaterThan(0));
            expect((font.rank, font.side), (0, ForumBodyRubySide.over));
            expect(bands.geometry.metrics.glyphHandleCount, before);
            expect(bands.contexts.first.localBands.single.isReserved, isFalse);
            expect(cache.activeLeases, 0);
            expect(cache.pictureBuildCount, 0);
            final builds = cache.layoutBuildCount;
            final lease = font.request.acquire(
              cache,
              width: bands.geometry.metrics.input.maxWidth,
              textScaler: value.textScaler,
              cachedOnly: true,
            )!;
            try {
              expect(lease.nativeInputIdentity, font.nativeInputIdentity);
              expect(lease.content, same(font.request.content));
            } finally {
              lease.release();
            }
            expect(cache.layoutBuildCount, builds);
            cache.close();
            expect(value.fonts.single.bounds, font.bounds);
            expect(() => value.fonts.clear(), throwsUnsupportedError);
            expect(
              () => value.effectiveScales[999] = 1,
              throwsUnsupportedError,
            );
          },
        );
      }
    }
  }
  test(
    'span rank, union side and deduplicated actual native keys stay explicit',
    () {
      final bands = _bands(
        '<ruby><rb>A</rb><rb>B</rb>'
        '<rtc style="font-size:8px"><rt rbspan="2"></rt></rtc>'
        '<rtc style="font-size:12px"><rt></rt><rt></rt></rtc></ruby>',
        cache,
      );
      final value = _finish(
        ForumBodyRubyEmptyAnnotationFontsPreparation(
          bands: bands,
          cache: cache,
          ensureOwner: () {},
          expectedTextScaler: TextScaler.noScaling,
        ),
        quantum: 32,
      );
      expect(value.fonts.map((f) => (f.rank, f.side)), [
        (0, ForumBodyRubySide.over),
        (1, ForumBodyRubySide.under),
        (1, ForumBodyRubySide.under),
      ]);
      expect(
        value.fonts.map((f) => f.nativeInputIdentity).toSet(),
        hasLength(2),
      );
      expect(value.fonts.map((f) => f.source.source.id).toSet(), hasLength(3));
      final probe = cache.createBudgetProbe(captureInputEstimates: true);
      try {
        for (final slot in value.fontMeasurementFootprint) {
          slot.request.includeBudget(
            probe,
            width: slot.width,
            minimumLineCount: slot.minimumLineCount,
            textScaler: value.textScaler,
          );
        }
        expect(
          probe.snapshotNativeIdentities(),
          value.fonts.map((f) => f.nativeInputIdentity).toSet(),
        );
        expect(probe.snapshotNativeIdentities(), hasLength(2));
      } finally {
        probe.close();
      }
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
    },
  );
  test(
    'base struts, populated RTs, collapsed fences and opaque inline sources are not empty RT fonts',
    () {
      for (final html in [
        '<ruby><rb></rb><rt>音</rt></ruby>',
        '<ruby><rb>漢</rb>\n<rb>字</rb><rt>a</rt>\n<rt>b</rt></ruby>',
        '<ruby><rb>L<ruby>A<rt></rt></ruby>R</rb><rt>y</rt></ruby>',
      ]) {
        final bands = _bands(html, cache);
        final before = (cache.layoutBuildCount, cache.hitCount);
        final value = _finish(
          ForumBodyRubyEmptyAnnotationFontsPreparation(
            bands: bands,
            cache: cache,
            ensureOwner: () {},
            expectedTextScaler: TextScaler.noScaling,
          ),
        );
        expect(value.fonts, isEmpty);
        expect(value.fontMeasurementFootprint, isEmpty);
        for (final source in bands.geometry.sources) {
          expect(value.fontForSource(source.source.id), isNull);
        }
        expect(() => value.fontForSource(100000), throwsArgumentError);
        expect((cache.layoutBuildCount, cache.hitCount), before);
      }
    },
  );
  test(
    'all new native font sizes freeze before shaping; existing glyph samples must match',
    () {
      final scaler = _Sizes(small: 1.5, large: 1);
      final bands = _bands(
        '<ruby><rb>A</rb><rb>B</rb><rt style="font-size:10px"></rt><rt style="font-size:12px"></rt></ruby>',
        cache,
        scaler: scaler,
      );
      expect(
        bands.geometry.metrics.effectiveGlyphScales.containsKey(10),
        isFalse,
      );
      final before = cache.layoutBuildCount;
      final value = _finish(
        ForumBodyRubyEmptyAnnotationFontsPreparation(
          bands: bands,
          cache: cache,
          ensureOwner: () {
            if (cache.layoutBuildCount > before) {
              scaler.small = 3;
              scaler.forbid = true;
            }
          },
          expectedTextScaler: scaler,
        ),
      );
      expect(value.effectiveScales[10], 15);
      expect(value.effectiveScales[12], 18);
      expect(value.fonts.map((f) => f.bounds.height), [15, 18]);
      final stale = ForumBodyRubyEmptyAnnotationFontsPreparation(
        bands: bands,
        cache: cache,
        ensureOwner: () {},
        expectedTextScaler: TextScaler.linear(2),
      );
      final built = cache.layoutBuildCount;
      expect(() => _finish(stale), throwsArgumentError);
      expect(cache.layoutBuildCount, built);
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'cached-only cold miss resumes and fresh warm measurements build no native resources',
    () {
      final bands = _bands('<ruby>A<rt></rt></ruby>', cache);
      cache.clearUnpinned();
      final work = ForumBodyRubyEmptyAnnotationFontsPreparation(
        bands: bands,
        cache: cache,
        ensureOwner: () {},
        expectedTextScaler: TextScaler.noScaling,
      );
      final builds = cache.layoutBuildCount;
      while (!work.cacheMiss) {
        work.advance(maxParts: 1, cachedOnly: true);
      }
      expect(cache.layoutBuildCount, builds);
      expect(work.nativeLeases, isEmpty);
      final first = _finish(work);
      final before = cache.layoutBuildCount;
      final warm = _finish(
        ForumBodyRubyEmptyAnnotationFontsPreparation(
          bands: bands,
          cache: cache,
          ensureOwner: () {},
          expectedTextScaler: TextScaler.noScaling,
        ),
        cachedOnly: true,
      );
      expect(
        warm.fonts.single.nativeInputIdentity,
        first.fonts.single.nativeInputIdentity,
      );
      expect(warm.fonts.single.bounds, first.fonts.single.bounds);
      expect(cache.layoutBuildCount, before);
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'foreign pin wait resumes the same font; an owned prefix that cannot fit fails explicitly',
    () {
      final bands = _bands('<ruby>A<rt></rt></ruby>', cache);
      for (final owned in [false, true]) {
        final small = ForumBodyParagraphCache(
          maxEntries: 1,
          maxEstimatedBytes: 1 << 24,
        );
        final base = bands.geometry.metrics.input.sources.firstWhere(
          (s) => s.needsNative,
        );
        final pin = bands.geometry.metrics.input
            .requestForSource(base.id)
            .acquire(
              small,
              width: 500,
              textScaler: TextScaler.noScaling,
              cachedOnly: false,
            )!;
        final work = ForumBodyRubyEmptyAnnotationFontsPreparation(
          bands: bands,
          cache: small,
          ensureOwner: () {},
          expectedTextScaler: TextScaler.noScaling,
          additionalOwnedLeases: owned ? () => [pin] : null,
        );
        try {
          if (owned) {
            expect(
              () => _finish(work),
              throwsA(
                isA<ForumBodyParagraphBudgetException>().having(
                  (e) => e.failure,
                  'failure',
                  ForumBodyParagraphBudgetFailure.content,
                ),
              ),
            );
            expect(pin.isActive, isTrue);
          } else {
            var waiting = false;
            for (var n = 0; !waiting; n++) {
              expect(n, lessThan(10000));
              waiting = work.advance(maxParts: 1).waitingForLayoutBudget;
            }
            final before = small.layoutBuildCount;
            expect(work.advance().formatUnitsPrepared, 0);
            expect(small.layoutBuildCount, before);
            pin.release();
            expect(_finish(work).fonts, hasLength(1));
          }
        } finally {
          work.close();
          pin.release();
          expect(small.activeLeases, 0);
          small.close();
        }
      }
    },
  );
  test(
    'retirement at every part, native acquisition and publication releases temporary fonts',
    () {
      final bands = _bands(
        '<ruby><rb>A</rb><rb>B</rb><rt></rt><rt style="font-size:12px"></rt></ruby>',
        cache,
      );
      final count = ForumBodyRubyEmptyAnnotationFontsPreparation(
        bands: bands,
        cache: cache,
        ensureOwner: () {},
        expectedTextScaler: TextScaler.noScaling,
      );
      var parts = 0;
      while (!count.isReady) {
        parts += count.advance(maxParts: 1).formatUnitsPrepared;
      }
      count.close();
      for (var stop = 0; stop <= parts; stop++) {
        var active = true;
        final work = ForumBodyRubyEmptyAnnotationFontsPreparation(
          bands: bands,
          cache: cache,
          ensureOwner: () {
            if (!active) throw StateError('retired');
          },
          expectedTextScaler: TextScaler.noScaling,
        );
        for (var n = 0; n < stop; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(work.advance, throwsStateError);
        expect(work.takeFonts, throwsStateError);
        work.close();
        expect(cache.activeLeases, 0);
      }
      cache.clearUnpinned();
      final builds = cache.layoutBuildCount;
      final nativeClose = ForumBodyRubyEmptyAnnotationFontsPreparation(
        bands: bands,
        cache: cache,
        ensureOwner: () {
          if (cache.layoutBuildCount > builds) {
            throw StateError('retired during acquisition');
          }
        },
        expectedTextScaler: TextScaler.noScaling,
      );
      expect(() => _finish(nativeClose), throwsStateError);
      expect(cache.activeLeases, 0);
      ForumBodyRubyEmptyAnnotationFontsPreparation? publication;
      publication = ForumBodyRubyEmptyAnnotationFontsPreparation(
        bands: bands,
        cache: cache,
        ensureOwner: () {
          if (publication?.isReady == true) publication!.close();
        },
        expectedTextScaler: TextScaler.noScaling,
      );
      expect(() => _finish(publication!), throwsStateError);
      expect(publication.takeFonts, throwsStateError);
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
    },
  );
  test(
    'caught reentry preserves the outer measurement and delivered numbers retain no owner callbacks',
    () {
      final bands = _bands('<ruby>A<rt></rt></ruby>', cache);
      var active = true, calls = 0;
      ForumBodyRubyEmptyAnnotationFontsPreparation? work;
      work = ForumBodyRubyEmptyAnnotationFontsPreparation(
        bands: bands,
        cache: cache,
        expectedTextScaler: TextScaler.noScaling,
        ensureOwner: () {
          calls++;
          if (!active) throw StateError('retired');
          if (work == null) return;
          expect(work.advance, throwsStateError);
          expect(work.takeFonts, throwsStateError);
        },
      );
      final result = _finish(work);
      final before = calls;
      active = false;
      cache.close();
      expect(result.fonts.single.bounds.height, greaterThan(0));
      expect(result.textScaler.scale(10), 10);
      expect(result.fontMeasurementFootprint, hasLength(1));
      expect(calls, before);
    },
  );
}
