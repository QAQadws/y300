import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_glyph_tree_fixture.dart';

const _nested =
    '<ruby style="font-size:26px;text-emphasis:\'X\' red;line-height:.4">'
    '<rb><ruby><rb>A é 👩‍👩‍👧‍👦</rb><rt style="font-size:8px">in</rt></ruby></rb>'
    '<rt style="font-size:12px;text-emphasis:\'Y\' blue">out</rt></ruby>';
const _segment =
    '<ruby style="text-emphasis:\'X\' red;line-height:.4">'
    '<rb>A</rb><rb style="font-size:32px">B</rb>'
    '<rtc><rt rbspan="2" style="font-size:12px;text-emphasis:\'Y\' blue">wide</rt></rtc>'
    '<rtc><rt></rt><rt></rt></rtc></ruby>';

final class _Curve extends TextScaler {
  const _Curve({this.overrides = const {}, this.forbid});
  final Map<double, double> overrides;
  final List<bool>? forbid;
  @override
  double scale(double size) {
    if (forbid?.single == true) {
      throw StateError('Raw scaler retained by native line');
    }
    return overrides[size] ?? size * (size < 20 ? 1.4 : 1.1);
  }

  @override
  double get textScaleFactor =>
      throw StateError('Use actual full/half font sizes');
}

ForumBodyRubyEmptyAnnotationFonts _fonts(
  String html,
  ForumBodyParagraphCache cache, {
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  bool banded = false,
}) {
  final bands = rubyGlyphTreeBandsFixture(
    html,
    cache,
    direction: direction,
    scaler: scaler,
    mapInput: banded
        ? (input) {
            final bases = input.sources
                .where(
                  (s) =>
                      s.needsNative &&
                      ['A', 'B'].contains(s.glyphs.projection.text),
                )
                .toList();
            expect(bases, hasLength(2));
            final band = ForumBodyTextBandContent(
              contexts: bases.map((s) => s.glyphs).toList(),
            );
            return input.mapGlyphRequests((request) {
              final index = band.contexts.indexOf(request.content);
              return index < 0
                  ? request
                  : ForumBodyTextRequest.bandChild(
                      band: band,
                      childIndex: index,
                    );
            });
          }
        : null,
  );
  final work = ForumBodyRubyEmptyAnnotationFontsPreparation(
    bands: bands,
    cache: cache,
    ensureOwner: () {},
    expectedTextScaler: scaler,
  );
  try {
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    return work.takeFonts();
  } finally {
    work.close();
  }
}

ForumBodyRubyTreeEmphasisMetrics _finish(
  ForumBodyRubyTreeEmphasisMetricsPreparation work, {
  bool cachedOnly = false,
  int quantum = 1,
}) {
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(20000));
      final step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.formatUnitsPrepared, inInclusiveRange(1, quantum));
      expect(step.layoutsBuilt, lessThanOrEqualTo(1));
      expect(step.picturesBuilt, 0);
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
    }
    expect(work.nativeLeases, isEmpty);
    return work.takeMetrics();
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
  for (final html in [_nested, _segment]) {
    for (final direction in TextDirection.values) {
      for (final nonlinear in [false, true]) {
        for (final banded in html == _segment ? [false, true] : [false]) {
          test(
            'actual source and full/half fonts $direction nonlinear=$nonlinear band=$banded $html',
            () {
              final scaler = nonlinear ? const _Curve() : TextScaler.noScaling;
              final fonts = _fonts(
                html,
                cache,
                direction: direction,
                scaler: scaler,
                banded: banded,
              );
              final geometry = fonts.bands.geometry;
              final glyphBox = geometry.metrics.box;
              final value = _finish(
                ForumBodyRubyTreeEmphasisMetricsPreparation(
                  emptyFonts: fonts,
                  cache: cache,
                  ensureOwner: () {},
                  expectedTextScaler: scaler,
                ),
              );
              final eligible = geometry.sources
                  .where(
                    (s) => s.source.needsNative && s.source.emphasis != null,
                  )
                  .toList();
              expect(
                value.sources.map((s) => s.source),
                orderedEquals(eligible),
              );
              expect(value.sources, hasLength(html == _nested ? 2 : 3));
              expect(value.emptyFonts, same(fonts));
              expect(value.geometry, same(geometry));
              for (final item in value.sources) {
                final source = item.source.source, line = item.line;
                final box = geometry.metrics.nodes[source.id].box!;
                expect(value.sourceForId(source.id), same(item));
                expect(line.input, same(source.emphasis));
                expect(line.input.content, same(source.content));
                expect(line.input.glyphInput.glyphs, same(source.glyphs));
                expect(
                  line.baseRequest,
                  same(geometry.metrics.input.requestForSource(source.id)),
                );
                expect(line.baseRequest.content, same(source.glyphs));
                expect(line.rowInput, isNull);
                expect(line.baseFontBounds, box.bounds);
                expect(line.baseAlphabeticBaseline, box.alphabeticBaseline);
                final lease = line.baseRequest.acquire(
                  cache,
                  width: 500,
                  textScaler: value.textScaler,
                  cachedOnly: true,
                )!;
                try {
                  expect(
                    lease.content.projection,
                    same(source.content.projection),
                  );
                } finally {
                  lease.release();
                }
                if (banded &&
                    ['A', 'B'].contains(source.content.projection.text)) {
                  expect(
                    line.baseRequest,
                    isA<ForumBodyTextBandChildRequest>(),
                  );
                }
                for (final slot in line.nativeFootprint) {
                  if (slot.request
                      case final ForumBodyEmphasisMarkRequest request) {
                    final native =
                        request.acquire(
                              cache,
                              width: slot.width,
                              textScaler: value.textScaler,
                              cachedOnly: true,
                            )
                            as ForumBodyEmphasisMarkLease;
                    final painter = TextPainter(
                      text: TextSpan(
                        text: request.input.mark,
                        style: request.input.textStyle,
                      ),
                      textDirection: direction,
                      textScaler: scaler,
                    )..layout();
                    try {
                      expect(native.layout.width, closeTo(painter.width, 1e-8));
                      expect(
                        native.layout.height,
                        closeTo(painter.height, 1e-8),
                      );
                      // Mark placement uses the physical line baseline; the
                      // paragraph baseline API is a separate native metric.
                      expect(
                        native.layout.alphabeticBaseline,
                        closeTo(
                          painter.computeLineMetrics().single.baseline,
                          1e-8,
                        ),
                      );
                    } finally {
                      native.release();
                      painter.dispose();
                    }
                  }
                }
                for (final mark in line.marks) {
                  final style = source
                      .content
                      .runs[line.input.units[mark.unitIndex].runIndex]
                      .style;
                  final half = style.textStyle.fontSize! / 2;
                  expect(mark.input.textStyle.fontSize, half);
                  expect(line.effectiveScales[half], scaler.scale(half));
                  expect(value.effectiveScales[half], scaler.scale(half));
                  expect(mark.input.textStyle.color, style.textEmphasis.color);
                }
              }
              if (html == _nested) {
                final base = value.sources.first.line;
                final start = base.input.content.projection.text.indexOf('é');
                expect(
                  base.marks.where(
                    (m) => base.input.units[m.unitIndex].startUtf16 == start,
                  ),
                  hasLength(1),
                );
                expect(
                  base.input.units
                      .singleWhere((u) => u.startUtf16 == start)
                      .endUtf16,
                  start + 2,
                );
                if (nonlinear) {
                  expect(value.effectiveScales[13], 18.2);
                  expect(
                    value.effectiveScales[13],
                    isNot(value.effectiveScales[26]! / 2),
                  );
                }
              }
              final probe = cache.createBudgetProbe();
              try {
                for (final slot in value.fontMeasurementFootprint) {
                  slot.request.includeBudget(
                    probe,
                    width: slot.width,
                    minimumLineCount: slot.minimumLineCount,
                    textScaler: value.textScaler,
                  );
                }
                expect(probe.snapshotNativeIdentities(), isNotEmpty);
                if (html == _segment && banded) {
                  expect(probe.snapshotNativeIdentities(), hasLength(6));
                }
              } finally {
                probe.close();
              }
              expect(geometry.metrics.box, same(glyphBox));
              expect(cache.activeLeases, 0);
              expect(cache.pictureBuildCount, 0);
              cache.close();
              expect(value.sources.first.line.marks, isNotEmpty);
              expect(() => value.sources.clear(), throwsUnsupportedError);
              expect(
                () => value.effectiveScales[999] = 1,
                throwsUnsupportedError,
              );
            },
          );
        }
      }
    }
  }
  for (final direction in TextDirection.values) {
    for (final nonlinear in [false, true]) {
      test(
        'styled grapheme uses governing run or preserves mixed-direction admission $direction nonlinear=$nonlinear',
        () {
          const html =
              '<ruby style="text-emphasis:\'X\' red"><rb>'
              '<span dir="rtl" style="font-size:26px">e</span>'
              '<span style="font-size:32px;text-emphasis:\'Y\' blue">́</span>'
              '</rb><rt>x</rt></ruby>';
          final scaler = nonlinear ? const _Curve() : TextScaler.noScaling;
          if (direction == TextDirection.ltr) {
            expect(
              () => _fonts(html, cache, direction: direction, scaler: scaler),
              throwsA(
                isA<ForumBodyParagraphLayoutException>().having(
                  (e) => e.failure,
                  'failure',
                  ForumBodyParagraphLayoutFailure.direction,
                ),
              ),
            );
            expect(cache.activeLeases, 0);
            return;
          }
          final fonts = _fonts(
            html,
            cache,
            direction: direction,
            scaler: scaler,
          );
          final value = _finish(
            ForumBodyRubyTreeEmphasisMetricsPreparation(
              emptyFonts: fonts,
              cache: cache,
              ensureOwner: () {},
              expectedTextScaler: scaler,
            ),
          );
          final line = value.sources.single.line,
              unit = line.input.units.single;
          expect((unit.startUtf16, unit.endUtf16), (0, 2));
          expect(line.marks, hasLength(1));
          expect(line.marks.single.input.mark, 'X');
          expect(line.marks.single.input.textDirection, TextDirection.rtl);
          expect(line.marks.single.input.textStyle.fontSize, 13);
          expect(
            line.marks.single.input.textStyle.color,
            const Color(0xffff0000),
          );
          expect(value.effectiveScales.containsKey(16), isFalse);
          expect(cache.activeLeases, 0);
          expect(cache.pictureBuildCount, 0);
        },
      );
    }
  }
  test(
    'explicit emphasis inside an original RT keeps its own source and ancestry',
    () {
      final fonts = _fonts(
        '<ruby style="text-emphasis:\'X\' red">AB'
        '<rt style="text-emphasis:\'Y\' blue"><ruby>XY<rt>xy</rt></ruby></rt></ruby>',
        cache,
      );
      final value = _finish(
        ForumBodyRubyTreeEmphasisMetricsPreparation(
          emptyFonts: fonts,
          cache: cache,
          ensureOwner: () {},
          expectedTextScaler: TextScaler.noScaling,
        ),
      );
      expect(
        value.sources.map((s) => s.source.source.content.projection.text),
        ['AB', 'XY'],
      );
      expect(
        value.sources.last.line.marks.every((m) => m.input.mark == 'Y'),
        isTrue,
      );
      expect(value.sources.last.source.node.parent, isNotNull);
      expect(value.geometry.sources.last.source.content.projection.text, 'xy');
    },
  );
  test(
    'punctuation preserves its original active source without a marker measurement',
    () {
      final fonts = _fonts(
        '<ruby style="text-emphasis:circle"><rb>.</rb><rt>x</rt></ruby>',
        cache,
      );
      final value = _finish(
        ForumBodyRubyTreeEmphasisMetricsPreparation(
          emptyFonts: fonts,
          cache: cache,
          ensureOwner: () {},
          expectedTextScaler: TextScaler.noScaling,
        ),
      );
      expect(value.sources, isEmpty);
      final source = value.geometry.sources.first.source;
      expect(source.content.style.textEmphasis.isEnabled, isTrue);
      expect(source.emphasis!.units, isEmpty);
      expect(value.sourceForId(source.id), isNull);
      expect(value.fontMeasurementFootprint, isEmpty);
      expect(cache.pictureBuildCount, 0);
    },
  );
  test(
    'plain, empty and opaque inline contexts cannot become independent marked leaves',
    () {
      for (final html in [
        '<ruby>A<rt></rt></ruby>',
        '<ruby style="text-emphasis:circle"><rb></rb><rt></rt></ruby>',
        '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>y</rt></ruby>',
      ]) {
        final fonts = _fonts(html, cache);
        final before = (cache.layoutBuildCount, cache.hitCount);
        final value = _finish(
          ForumBodyRubyTreeEmphasisMetricsPreparation(
            emptyFonts: fonts,
            cache: cache,
            ensureOwner: () {},
            expectedTextScaler: TextScaler.noScaling,
          ),
        );
        expect(value.sources, isEmpty);
        for (final source in value.geometry.sources) {
          expect(value.sourceForId(source.source.id), isNull);
        }
        expect(() => value.sourceForId(100000), throwsArgumentError);
        expect((cache.layoutBuildCount, cache.hitCount), before);
      }
    },
  );
  test(
    'new half sizes freeze before first native build and do not retain the caller',
    () {
      final forbid = [false], scaler = _Curve(forbid: [false]);
      final mutable = _Curve(forbid: forbid);
      final fonts = _fonts(_segment, cache, scaler: scaler);
      expect(fonts.effectiveScales.containsKey(16), isFalse);
      cache.clearUnpinned();
      final before = cache.layoutBuildCount;
      final value = _finish(
        ForumBodyRubyTreeEmphasisMetricsPreparation(
          emptyFonts: fonts,
          cache: cache,
          ensureOwner: () {
            if (cache.layoutBuildCount > before) {
              forbid[0] = true;
            }
          },
          expectedTextScaler: mutable,
        ),
      );
      expect(forbid.single, isTrue);
      expect(value.effectiveScales[16], 22.4);
      expect(value.sources[1].line.effectiveScales[16], 22.4);
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'stale glyph or empty RT samples and invalid half scaling fail before native work',
    () {
      final fonts = _fonts(
        '<ruby style="font-size:26px;text-emphasis:circle">A<rt style="font-size:12px"></rt></ruby>',
        cache,
        scaler: const _Curve(),
      );
      for (final scaler in [
        TextScaler.linear(2),
        _Curve(overrides: {12: 18}),
        _Curve(overrides: {13: double.nan}),
        _Curve(overrides: {13: 0}),
        _Curve(overrides: {13: 5000}),
      ]) {
        final before = cache.layoutBuildCount;
        final work = ForumBodyRubyTreeEmphasisMetricsPreparation(
          emptyFonts: fonts,
          cache: cache,
          ensureOwner: () {},
          expectedTextScaler: scaler,
        );
        expect(() => _finish(work), throwsArgumentError);
        expect(work.failedRequest, isNull);
        expect(cache.layoutBuildCount, before);
        expect(cache.activeLeases, 0);
      }
    },
  );
  test(
    'cold cached-only measurement resumes; warm measurement records and shapes nothing',
    () {
      final fonts = _fonts(_segment, cache, banded: true);
      cache.clearUnpinned();
      final before = cache.layoutBuildCount;
      final work = ForumBodyRubyTreeEmphasisMetricsPreparation(
        emptyFonts: fonts,
        cache: cache,
        ensureOwner: () {},
        expectedTextScaler: TextScaler.noScaling,
      );
      for (var n = 0; !work.cacheMiss; n++) {
        expect(n, lessThan(20000));
        work.advance(maxParts: 1, cachedOnly: true);
      }
      expect(cache.layoutBuildCount, before);
      final first = _finish(work);
      final built = cache.layoutBuildCount;
      final second = _finish(
        ForumBodyRubyTreeEmphasisMetricsPreparation(
          emptyFonts: fonts,
          cache: cache,
          ensureOwner: () {},
          expectedTextScaler: TextScaler.noScaling,
        ),
        cachedOnly: true,
        quantum: 32,
      );
      expect(
        second.sources.map((s) => s.line.baseFontBounds),
        first.sources.map((s) => s.line.baseFontBounds),
      );
      expect(cache.layoutBuildCount, built);
      expect(cache.pictureBuildCount, 0);
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'external pins wait while an owned prefix that cannot fit fails without releasing caller leases',
    () {
      final fonts = _fonts(
        '<ruby style="text-emphasis:\'X\' red">A<rt>x</rt></ruby>',
        cache,
      );
      final input = fonts.bands.geometry.metrics.input;
      final rt = input.sources.last;
      for (final owned in [false, true]) {
        final small = ForumBodyParagraphCache(
          maxEntries: 2,
          maxEstimatedBytes: 1 << 24,
        );
        final pin = input
            .requestForSource(rt.id)
            .acquire(
              small,
              width: 500,
              textScaler: TextScaler.noScaling,
              cachedOnly: false,
            )!;
        final work = ForumBodyRubyTreeEmphasisMetricsPreparation(
          emptyFonts: fonts,
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
            for (var n = 0; ; n++) {
              expect(n, lessThan(20000));
              if (work.advance(maxParts: 1).waitingForLayoutBudget) break;
            }
            final builds = small.layoutBuildCount;
            expect(work.advance().formatUnitsPrepared, 0);
            expect(small.layoutBuildCount, builds);
            pin.release();
            expect(_finish(work).sources, hasLength(1));
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
    'every work part, actual native acquisition and final publication reject retirement',
    () {
      final fonts = _fonts(
        '<ruby style="text-emphasis:\'X\' red"><rb>A</rb><rb>B</rb><rt>a</rt><rt>b</rt></ruby>',
        cache,
      );
      final count = ForumBodyRubyTreeEmphasisMetricsPreparation(
        emptyFonts: fonts,
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
        final work = ForumBodyRubyTreeEmphasisMetricsPreparation(
          emptyFonts: fonts,
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
        expect(work.takeMetrics, throwsStateError);
        work.close();
        expect(cache.activeLeases, 0);
      }
      cache.clearUnpinned();
      final builds = cache.layoutBuildCount;
      final nativeClose = ForumBodyRubyTreeEmphasisMetricsPreparation(
        emptyFonts: fonts,
        cache: cache,
        ensureOwner: () {
          if (cache.layoutBuildCount > builds) {
            throw StateError('retired during shape');
          }
        },
        expectedTextScaler: TextScaler.noScaling,
      );
      expect(() => _finish(nativeClose), throwsStateError);
      expect(cache.activeLeases, 0);
      ForumBodyRubyTreeEmphasisMetricsPreparation? publication;
      publication = ForumBodyRubyTreeEmphasisMetricsPreparation(
        emptyFonts: fonts,
        cache: cache,
        ensureOwner: () {
          if (publication?.isReady == true) publication!.close();
        },
        expectedTextScaler: TextScaler.noScaling,
      );
      expect(() => _finish(publication!), throwsStateError);
      expect(publication.takeMetrics, throwsStateError);
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'caught reentry preserves outer work and numeric results survive owner closure',
    () {
      final fonts = _fonts(_nested, cache);
      var active = true, calls = 0;
      ForumBodyRubyTreeEmphasisMetricsPreparation? work;
      work = ForumBodyRubyTreeEmphasisMetricsPreparation(
        emptyFonts: fonts,
        cache: cache,
        expectedTextScaler: TextScaler.noScaling,
        ensureOwner: () {
          calls++;
          if (!active) throw StateError('retired');
          if (work == null) return;
          expect(work.advance, throwsStateError);
          expect(work.takeMetrics, throwsStateError);
        },
      );
      final value = _finish(work);
      final before = calls;
      active = false;
      cache.close();
      expect(value.sources.first.line.marks, isNotEmpty);
      expect(value.textScaler.scale(13), 13);
      expect(value.fontMeasurementFootprint, isNotEmpty);
      expect(calls, before);
    },
  );
}
