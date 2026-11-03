import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_glyph_tree_fixture.dart';

const _nested =
    '<ruby style="text-emphasis:circle;background:#ff000080;line-height:.4">'
    '<rb><ruby style="background:#0000ff80"><rb>A é</rb><rt>x</rt></ruby></rb>'
    '<rt style="text-emphasis:sesame"> yz </rt></ruby>';
const _segment =
    '<ruby style="text-emphasis:circle"><rb>A</rb> <rb>B</rb>'
    '<rtc><rt>x</rt> <rt>y</rt></rtc><rtc><rt></rt><rt>z</rt></rtc></ruby>';
const _mixed =
    '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb>'
    '<rt style="text-emphasis:circle">z</rt></ruby>';

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 20 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Sample actual sizes');
}

ForumBodyRubyGlyphTreeBinding _finish(
  ForumBodyRubyGlyphTreeBindingPreparation work, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(30000));
      final step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.formatUnitsPrepared, inInclusiveRange(0, quantum));
      expect(step.partsPrepared, greaterThanOrEqualTo(0));
      expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
    }
    return work.takeBinding();
  } finally {
    work.close();
  }
}

Future<List<int>> _pixels(void Function(Canvas) paint, int ratio) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(ratio.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(250 * ratio, 180 * ratio);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  late ForumBodyParagraphCache cache;
  setUp(() {
    cache = ForumBodyParagraphCache(
      maxEntries: 512,
      maxEstimatedBytes: 1 << 26,
    );
  });
  tearDown(() {
    expect(cache.activeLeases, 0);
    cache.close();
  });

  for (final (fixture, html) in [
    _nested,
    _segment,
    _mixed,
    '<ruby style="text-emphasis:circle"><rb></rb><rt></rt></ruby>',
  ].indexed) {
    for (final direction in TextDirection.values) {
      for (final nonlinear in [false, true]) {
        test(
          'original/native source binding fixture=$fixture $direction nonlinear=$nonlinear',
          () {
            final scaler = nonlinear ? const _Curve() : TextScaler.noScaling;
            final geometry = rubyGlyphTreeBandsFixture(
              html,
              cache,
              direction: direction,
              scaler: scaler,
            ).geometry;
            final input = geometry.metrics.input;
            final value = _finish(
              ForumBodyRubyGlyphTreeBindingPreparation(
                geometry: geometry,
                cache: cache,
                ensureOwner: () {},
                expectedTextScaler: scaler,
              ),
            );
            try {
              expect(value.geometry, same(geometry));
              expect(value.isOwnedBy(cache), isTrue);
              expect(
                value.sources.map((s) => s.source),
                orderedEquals(input.sources),
              );
              for (final bound in value.sources) {
                final source = bound.source;
                expect(value.sourceForId(source.id), same(bound));
                expect(bound.position, same(geometry.sourceForId(source.id)));
                if (source.needsNative) {
                  final lease = input
                      .requestForSource(source.id)
                      .acquire(
                        cache,
                        width: input.maxWidth,
                        textScaler: geometry.metrics.glyphTextScaler,
                        cachedOnly: true,
                      )!;
                  try {
                    expect(
                      bound.glyphNativeInputIdentity,
                      lease.nativeInputIdentity,
                    );
                    final boxes = value.glyphSelectionBoxes(
                      sourceId: source.id,
                      startUtf16: 0,
                      endUtf16: source.content.projection.text.length,
                    );
                    final expected = lease.layout.selectionBoxes(
                      0,
                      source.glyphs.projection.text.length,
                    );
                    expect(
                      boxes.map((b) => b.toRect()),
                      expected.map(
                        (b) => b.toRect().shift(bound.position.contextOrigin),
                      ),
                    );
                  } finally {
                    lease.release();
                  }
                } else {
                  expect(bound.glyphNativeInputIdentity, isNull);
                }
                if (source.content.isSourceFree ||
                    source.content.projection.text.isEmpty) {
                  continue;
                }
                final boxes = value.glyphSelectionBoxes(
                  sourceId: source.id,
                  startUtf16: 0,
                  endUtf16: source.content.projection.text.length,
                  paintedOnly: true,
                );
                for (final box in boxes.where((b) => b.toRect().width > 1e-6)) {
                  final hit = value.sourceAtGlyph(box.toRect().center);
                  expect(hit.nodeIndex, source.id);
                  expect(hit.content, same(source.content));
                  expect(
                    hit.position.sourceRune,
                    source.content.projection
                        .sourceAtUtf16(hit.position.displayUtf16)
                        .sourceRune,
                  );
                }
                if (bound.usesInlineParent) {
                  expect(source.content, same(source.glyphs));
                }
              }
              if (html == _mixed) {
                expect(value.sources.any((s) => s.usesInlineParent), isTrue);
              }
              expect(() => value.sources.clear(), throwsUnsupportedError);
              expect(() => value.sourceForId(99999), throwsArgumentError);
            } finally {
              value.close();
            }
            expect(value.isActive, isFalse);
            expect(value.nativeLeases, isEmpty);
            // Pure source/key metadata must not retain a live native lease.
            expect(value.sources.length, input.sources.length);
            expect(() => value.sourceAtGlyph(Offset.zero), throwsStateError);
          },
        );
      }
    }
  }
  for (final ratio in [1, 2]) {
    test(
      'glyph plane pixels preserve actual fonts and alpha backgrounds DPR$ratio',
      () async {
        final geometry = rubyGlyphTreeBandsFixture(_nested, cache).geometry;
        final value = _finish(
          ForumBodyRubyGlyphTreeBindingPreparation(
            geometry: geometry,
            cache: cache,
            ensureOwner: () {},
            expectedTextScaler: TextScaler.noScaling,
          ),
        );
        final leases = <({ForumBodyTextLease lease, Offset origin})>[];
        try {
          for (final source in geometry.sources.where(
            (s) => s.source.needsNative,
          )) {
            leases.add((
              lease: geometry.metrics.input
                  .requestForSource(source.source.id)
                  .acquire(
                    cache,
                    width: 500,
                    textScaler: geometry.metrics.glyphTextScaler,
                    cachedOnly: true,
                  )!,
              origin: source.contextOrigin,
            ));
          }
          const origin = Offset(12.3, 17.7);
          final counters = (cache.layoutBuildCount, cache.pictureBuildCount);
          final actual = await _pixels((canvas) {
            value.paintBackgrounds(
              canvas,
              origin,
              clip: const Rect.fromLTWH(0, 0, 250, 180),
            );
            value.paintGlyphs(canvas, origin);
          }, ratio);
          final expected = await _pixels((canvas) {
            for (final surface in value.backgrounds) {
              canvas.drawRect(
                surface.rect.shift(origin),
                Paint()..color = surface.font.background.color,
              );
            }
            for (final source in leases) {
              source.lease.layout.paint(canvas, origin + source.origin);
            }
          }, ratio);
          expect(actual, expected);
          expect(actual.any((byte) => byte > 0), isTrue);
          expect((cache.layoutBuildCount, cache.pictureBuildCount), counters);
        } finally {
          for (final source in leases) {
            source.lease.release();
          }
          value.close();
        }
      },
    );
  }
  test(
    'actual shared band aliases retain one real native key and original sources',
    () {
      final geometry = rubyGlyphTreeBandsFixture(
        _segment,
        cache,
        mapInput: (input) {
          final bases = input.sources
              .where((s) => ['A', 'B'].contains(s.glyphs.projection.text))
              .toList();
          final band = ForumBodyTextBandContent(
            contexts: bases.map((s) => s.glyphs).toList(),
          );
          return input.mapGlyphRequests((r) {
            final index = band.contexts.indexOf(r.content);
            return index < 0
                ? r
                : ForumBodyTextRequest.bandChild(band: band, childIndex: index);
          });
        },
      ).geometry;
      final value = _finish(
        ForumBodyRubyGlyphTreeBindingPreparation(
          geometry: geometry,
          cache: cache,
          ensureOwner: () {},
          expectedTextScaler: TextScaler.noScaling,
        ),
      );
      try {
        final bases = value.sources
            .where((s) => ['A', 'B'].contains(s.source.content.projection.text))
            .toList();
        expect(bases, hasLength(2));
        expect(
          bases.first.glyphNativeInputIdentity,
          bases.last.glyphNativeInputIdentity,
        );
        expect(
          bases.first.source.content,
          isNot(same(bases.last.source.content)),
        );
      } finally {
        value.close();
      }
    },
  );
  test(
    'cold cached-only miss resumes and warm binding does no native work',
    () {
      final geometry = rubyGlyphTreeBandsFixture(_mixed, cache).geometry;
      cache.clearUnpinned();
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final work = ForumBodyRubyGlyphTreeBindingPreparation(
        geometry: geometry,
        cache: cache,
        ensureOwner: () {},
        expectedTextScaler: TextScaler.noScaling,
      );
      for (var n = 0; !work.cacheMiss; n++) {
        expect(n, lessThan(20000));
        work.advance(maxParts: 1, cachedOnly: true);
      }
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      final first = _finish(work);
      first.close();
      final built = (cache.layoutBuildCount, cache.pictureBuildCount);
      final second = _finish(
        ForumBodyRubyGlyphTreeBindingPreparation(
          geometry: geometry,
          cache: cache,
          ensureOwner: () {},
          expectedTextScaler: TextScaler.noScaling,
        ),
        cachedOnly: true,
        quantum: 32,
      );
      second.close();
      expect((cache.layoutBuildCount, cache.pictureBuildCount), built);
    },
  );
  test(
    'stale scaler fails before native binding and owner guards retire paint/hit',
    () {
      final geometry = rubyGlyphTreeBandsFixture(_nested, cache).geometry;
      final before = cache.layoutBuildCount;
      final stale = ForumBodyRubyGlyphTreeBindingPreparation(
        geometry: geometry,
        cache: cache,
        ensureOwner: () {},
        expectedTextScaler: TextScaler.linear(2),
      );
      expect(
        () => _finish(stale),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      expect(cache.layoutBuildCount, before);
      var active = true;
      final value = _finish(
        ForumBodyRubyGlyphTreeBindingPreparation(
          geometry: geometry,
          cache: cache,
          ensureOwner: () {
            if (!active) throw StateError('retired');
          },
          expectedTextScaler: TextScaler.noScaling,
        ),
      );
      active = false;
      try {
        expect(() => value.sourceAtGlyph(Offset.zero), throwsStateError);
        expect(() => value.backgrounds, throwsStateError);
        final recorder = ui.PictureRecorder();
        try {
          expect(
            () => value.paintGlyphs(Canvas(recorder), Offset.zero),
            throwsStateError,
          );
        } finally {
          recorder.endRecording().dispose();
        }
      } finally {
        value.close();
      }
    },
  );
  test(
    'external pins resume while owned impossible prefixes fail without stealing leases',
    () {
      final geometry = rubyGlyphTreeBandsFixture(
        '<ruby style="text-emphasis:circle">A<rt>x</rt></ruby>',
        cache,
      ).geometry;
      final unrelated = rubyGlyphTreeBandsFixture(
        '<ruby>Q<rt></rt></ruby>',
        cache,
      ).geometry.metrics.input;
      final request = unrelated.requestForSource(unrelated.sources.first.id);
      for (final owned in [false, true]) {
        final small = ForumBodyParagraphCache(
          maxEntries: 2,
          maxEstimatedBytes: 1 << 24,
        );
        final pin = request.acquire(
          small,
          width: 500,
          textScaler: TextScaler.noScaling,
          cachedOnly: false,
        )!;
        final work = ForumBodyRubyGlyphTreeBindingPreparation(
          geometry: geometry,
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
            final builds = (small.layoutBuildCount, small.pictureBuildCount);
            expect(work.advance().waitingForLayoutBudget, isTrue);
            expect((small.layoutBuildCount, small.pictureBuildCount), builds);
            pin.release();
            final value = _finish(work);
            expect(value.isOwnedBy(small), isTrue);
            value.close();
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
    'every binding boundary, native shape and final publication retire cleanly',
    () {
      final geometry = rubyGlyphTreeBandsFixture(_nested, cache).geometry;
      final counter = ForumBodyRubyGlyphTreeBindingPreparation(
        geometry: geometry,
        cache: cache,
        ensureOwner: () {},
        expectedTextScaler: TextScaler.noScaling,
      );
      var parts = 0;
      while (!counter.isReady) {
        parts += counter.advance(maxParts: 1).formatUnitsPrepared;
      }
      counter.close();
      for (var stop = 0; stop <= parts; stop++) {
        var active = true;
        final work = ForumBodyRubyGlyphTreeBindingPreparation(
          geometry: geometry,
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
        expect(work.takeBinding, throwsStateError);
        work.close();
        expect(cache.activeLeases, 0);
      }
      cache.clearUnpinned();
      final before = cache.layoutBuildCount;
      final native = ForumBodyRubyGlyphTreeBindingPreparation(
        geometry: geometry,
        cache: cache,
        ensureOwner: () {
          if (cache.layoutBuildCount > before) throw StateError('retired');
        },
        expectedTextScaler: TextScaler.noScaling,
      );
      expect(() => _finish(native), throwsStateError);
      expect(cache.activeLeases, 0);
      ForumBodyRubyGlyphTreeBindingPreparation? publication;
      publication = ForumBodyRubyGlyphTreeBindingPreparation(
        geometry: geometry,
        cache: cache,
        ensureOwner: () {
          if (publication?.isReady == true) publication!.close();
        },
        expectedTextScaler: TextScaler.noScaling,
      );
      expect(() => _finish(publication!), throwsStateError);
    },
  );
  test(
    'caught reentry preserves outer transaction and cache close revokes delivery',
    () {
      final geometry = rubyGlyphTreeBandsFixture(_nested, cache).geometry;
      ForumBodyRubyGlyphTreeBindingPreparation? work;
      work = ForumBodyRubyGlyphTreeBindingPreparation(
        geometry: geometry,
        cache: cache,
        ensureOwner: () {
          if (work == null) return;
          expect(work.advance, throwsStateError);
          expect(work.takeBinding, throwsStateError);
        },
        expectedTextScaler: TextScaler.noScaling,
      );
      final value = _finish(work);
      cache.close();
      expect(value.isActive, isFalse);
      expect(value.isOwnedBy(cache), isFalse);
      expect(value.ensureActive, throwsStateError);
      value.close();
    },
  );
}
