import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_glyph_tree_fixture.dart';

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 20 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyRubyTreeEmphasisPlan _finish(
  ForumBodyRubyTreeEmphasisPlanPreparation work, {
  int quantum = 1,
}) {
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(30000));
      expect(work.advance(maxParts: quantum), inInclusiveRange(1, quantum));
    }
    return work.takePlan();
  } finally {
    work.close();
  }
}

ForumBodyRubyTreeEmphasisPlan _plan(
  ForumBodyRubyTreeEmphasisPlacement placement,
) => _finish(
  ForumBodyRubyTreeEmphasisPlanPreparation(
    placement: placement,
    ensureOwner: () {},
  ),
);

const _nested =
    '<ruby style="text-emphasis:circle;line-height:.4"><rb><ruby>A é'
    '<rt style="font-size:18px"></rt></ruby></rb>'
    '<rt style="text-emphasis:sesame">XY</rt></ruby>';
const _mixed =
    '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb>'
    '<rt style="text-emphasis:circle">z</rt></ruby>';

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

  for (final direction in TextDirection.values) {
    for (final nonlinear in [false, true]) {
      for (final (fixture, html) in [
        _nested,
        _mixed,
        '<ruby style="ruby-position:under;text-emphasis:circle;text-emphasis-position:under">'
            '<rb>A</rb><rb>B</rb><rtc><rt style="font-size:32px"></rt><rt>b</rt></rtc></ruby>',
      ].indexed) {
        test(
          'actual commands, root frame and full budget fixture=$fixture $direction nonlinear=$nonlinear',
          () {
            final scaler = nonlinear ? const _Curve() : TextScaler.noScaling;
            final placement = rubyTreeEmphasisPlacementFixture(
              html,
              cache,
              direction: direction,
              scaler: scaler,
            );
            final before = (
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
            );
            final plan = _plan(placement),
                metrics = placement.input.input,
                glyph = metrics.geometry.metrics;
            expect(plan.placement, same(placement));
            expect((
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
            ), before);
            final scene = plan.markerPictureInput!;
            expect(scene.commands, hasLength(placement.marks.length));
            final keys = <Object>{};
            for (var i = 0; i < scene.commands.length; i++) {
              final command = scene.commands[i],
                  placed = placement.marks[i],
                  mark = placed.mark;
              final request = ForumBodyEmphasisMarkRequest(mark.input);
              final lease = request.acquire(
                cache,
                width: glyph.input.maxWidth,
                textScaler: metrics.textScaler,
                cachedOnly: true,
              )!;
              try {
                expect(command.nativeInputIdentity, lease.nativeInputIdentity);
                keys.add(lease.nativeInputIdentity);
              } finally {
                lease.release();
              }
              expect(command.offset, placed.fontOffset);
              expect(command.fitScale, mark.fitScale);
              expect(
                command.translations,
                placed.baselineOrigin == Offset.zero
                    ? isEmpty
                    : [placed.baselineOrigin],
              );
              expect(command.bandChildIndex, isNull);
              expect(command.paragraphRow, isNull);
              expect(command.physicalLine, isNull);
            }
            final frame = glyph.root.font.encloseBounds(
              childBounds: placement.bounds,
              childBaseline: glyph.box.alphabeticBaseline,
            );
            expect(
              (
                plan.frame.size,
                plan.frame.baseline,
                plan.frame.childOffset,
                plan.frame.childBounds,
              ),
              (
                frame.size,
                frame.baseline,
                frame.childOffset,
                frame.childBounds,
              ),
            );
            final work = ForumBodyRubyGlyphTreeBindingPreparation(
              geometry: metrics.geometry,
              cache: cache,
              ensureOwner: () {},
              expectedTextScaler: scaler,
            );
            late ForumBodyRubyGlyphTreeBinding binding;
            try {
              while (!work.isReady) {
                work.advance(maxParts: 1);
              }
              binding = work.takeBinding();
            } finally {
              work.close();
            }
            try {
              expect(plan.retainedHandleCount, binding.nativeLeases.length + 1);
              keys.addAll(
                binding.nativeLeases.map((lease) => lease.nativeInputIdentity),
              );
              final probe = cache.createBudgetProbe(),
                  expected = cache.createBudgetProbe();
              try {
                for (final slot in plan.nativeBudgetFootprint) {
                  slot.request.includeBudget(
                    probe,
                    width: slot.width,
                    minimumLineCount: slot.minimumLineCount,
                    textScaler: metrics.textScaler,
                  );
                }
                for (final lease in binding.nativeLeases) {
                  expected.includeLease(lease);
                }
                for (final source in metrics.sources) {
                  for (final slot in source.line.nativeFootprint) {
                    slot.request.includeBudget(
                      expected,
                      width: slot.width,
                      minimumLineCount: slot.minimumLineCount,
                      textScaler: metrics.textScaler,
                    );
                  }
                }
                expected.includeTextPicture(scene);
                expect(
                  probe.snapshotNativeIdentities(),
                  expected.snapshotNativeIdentities(),
                );
                expect(probe.snapshotNativeIdentities(), containsAll(keys));
                expect(
                  probe.snapshotNativeIdentities().length,
                  keys.length + 1,
                );
                expect(
                  plan.nativeBudgetFootprint.where(
                    (s) => s.request is ForumBodyTextPictureBudgetInput,
                  ),
                  hasLength(1),
                );
                for (final font in metrics.emptyFonts.fonts) {
                  expect(
                    probe.snapshotNativeIdentities(),
                    isNot(contains(font.nativeInputIdentity)),
                  );
                }
              } finally {
                probe.close();
                expected.close();
              }
            } finally {
              binding.close();
            }
            cache.close();
            expect(plan.markerPictureInput!.commands, isNotEmpty);
            expect(
              () => plan.markerPictureInput!.commands.clear(),
              throwsUnsupportedError,
            );
          },
        );
      }
    }
  }
  test(
    'zero target plans have no scene request, fake marker or extra retained slot',
    () {
      for (final html in [
        '<ruby>A<rt></rt></ruby>',
        '<ruby style="text-emphasis:circle">.<rt>x</rt></ruby>',
        '<ruby style="text-emphasis:circle"><rb></rb><rt></rt></ruby>',
        '<ruby style="font-size:17.3px;line-height:.4"><rb><ruby>A<rt>x</rt></ruby></rb><rt>z</rt></ruby>',
      ]) {
        final placement = rubyTreeEmphasisPlacementFixture(html, cache),
            plan = _plan(placement);
        expect(placement.marks, isEmpty);
        expect(plan.markerPictureInput, isNull);
        final glyph = placement.input.input.geometry.metrics;
        expect(plan.frame.size, glyph.box.bounds.size);
        expect(plan.frame.baseline, glyph.box.alphabeticBaseline);
        expect(plan.frame.childOffset, Offset.zero);
        expect(
          plan.retainedHandleCount,
          placement.input.input.geometry.metrics.glyphHandleCount,
        );
        expect(
          plan.nativeBudgetFootprint.any(
            (slot) => slot.request is ForumBodyTextPictureBudgetInput,
          ),
          isFalse,
        );
      }
    },
  );
  test(
    'actual scene budget rejects a font-only capacity without native mutation',
    () {
      final placement = rubyTreeEmphasisPlacementFixture(
        '<ruby style="text-emphasis:circle">A<rt style="font-size:32px"></rt></ruby>',
        cache,
      );
      final plan = _plan(placement),
          small = ForumBodyParagraphCache(
            maxEntries: 2,
            maxEstimatedBytes: 1 << 24,
          );
      final probe = small.createBudgetProbe();
      try {
        expect(
          () {
            for (final slot in plan.nativeBudgetFootprint) {
              slot.request.includeBudget(
                probe,
                width: slot.width,
                minimumLineCount: slot.minimumLineCount,
                textScaler: placement.input.input.textScaler,
              );
            }
          },
          throwsA(
            isA<ForumBodyParagraphBudgetException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphBudgetFailure.content,
            ),
          ),
        );
        expect(
          (small.layoutBuildCount, small.pictureBuildCount, small.activeLeases),
          (0, 0, 0),
        );
      } finally {
        probe.close();
        small.close();
      }
    },
  );
  test('actual command limit rejects rather than dropping original units', () {
    final placement = rubyTreeEmphasisPlacementFixture(
      '<ruby style="text-emphasis:circle">ABC<rt>x</rt></ruby>',
      cache,
    );
    final before = (
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.activeLeases,
    );
    final work = ForumBodyRubyTreeEmphasisPlanPreparation(
      placement: placement,
      ensureOwner: () {},
      maxCommands: 2,
    );
    expect(() => _finish(work), throwsArgumentError);
    expect((
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.activeLeases,
    ), before);
    expect(
      () => ForumBodyRubyTreeEmphasisPlanPreparation(
        placement: placement,
        ensureOwner: () {},
        maxCommands: 0,
      ),
      throwsArgumentError,
    );
  });
  test(
    'every command/publication boundary retires and caught reentry preserves work',
    () {
      final placement = rubyTreeEmphasisPlacementFixture(_nested, cache);
      final count = ForumBodyRubyTreeEmphasisPlanPreparation(
        placement: placement,
        ensureOwner: () {},
      );
      var parts = 0;
      while (!count.isReady) {
        parts += count.advance(maxParts: 1);
      }
      count.close();
      for (var stop = 0; stop <= parts; stop++) {
        var active = true;
        final work = ForumBodyRubyTreeEmphasisPlanPreparation(
          placement: placement,
          ensureOwner: () {
            if (!active) throw StateError('retired');
          },
        );
        for (var n = 0; n < stop; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(work.advance, throwsStateError);
        expect(work.takePlan, throwsStateError);
        work.close();
      }
      ForumBodyRubyTreeEmphasisPlanPreparation? publication;
      publication = ForumBodyRubyTreeEmphasisPlanPreparation(
        placement: placement,
        ensureOwner: () {
          if (publication?.isReady == true) publication!.close();
        },
      );
      expect(() => _finish(publication!), throwsStateError);
      ForumBodyRubyTreeEmphasisPlanPreparation? reentry;
      reentry = ForumBodyRubyTreeEmphasisPlanPreparation(
        placement: placement,
        ensureOwner: () {
          if (reentry == null) return;
          expect(reentry.advance, throwsStateError);
          expect(reentry.takePlan, throwsStateError);
        },
      );
      expect(_finish(reentry).markerPictureInput, isNotNull);
    },
  );
  test('wide cooperative composition is identical across work quanta', () {
    final placement = rubyTreeEmphasisPlacementFixture(
      '<ruby style="font-size:4px;text-emphasis:circle">'
      '${List.filled(48, '<rb>A</rb>').join()}<rtc>${List.filled(48, '<rt></rt>').join()}</rtc></ruby>',
      cache,
    );
    final single = _plan(placement),
        batch = _finish(
          ForumBodyRubyTreeEmphasisPlanPreparation(
            placement: placement,
            ensureOwner: () {},
          ),
          quantum: 32,
        );
    expect(batch.markerPictureInput, single.markerPictureInput);
    expect(
      batch.markerPictureInput.hashCode,
      single.markerPictureInput.hashCode,
    );
    expect(batch.frame.size, single.frame.size);
  });
}
