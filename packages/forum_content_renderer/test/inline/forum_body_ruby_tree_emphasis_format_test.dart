import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_glyph_tree_fixture.dart';
import 'test_support/ruby_tree_emphasis_scene_fixture.dart';

const _simple = '<ruby style="text-emphasis:circle">AB<rt>x</rt></ruby>';

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 20 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyRubyTreeEmphasisPlan _finish(
  ForumBodyRubyTreeEmphasisFormatPreparation work, {
  bool cachedOnly = false,
  int quantum = 1,
  void Function(int)? onParts,
}) {
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(30000));
      final step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.formatUnitsPrepared, inInclusiveRange(1, quantum));
      expect(step.layoutsBuilt, lessThanOrEqualTo(1));
      expect(step.picturesBuilt, 0);
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
      onParts?.call(step.formatUnitsPrepared);
    }
    expect(work.nativeLeases, isEmpty);
    return work.takePlan();
  } finally {
    work.close();
  }
}

ForumBodyRubyGlyphTreeMetrics _align(
  ForumBodyRubyGlyphTreeMetrics original,
  ForumBodyRubyGlyphTreeMetrics neighbor,
) => original.withAlignedRoot(switch ((original.rootAtom, neighbor.rootAtom)) {
  (
    ForumBodyRubyColumnMetrics(value: final old),
    ForumBodyRubyColumnMetrics(:final value),
  ) =>
    ForumBodyRubyAtomMetrics.column(
      old.alignedTo(ForumBodyRubyLevelMetrics.single(value).include(old)),
    ),
  (
    ForumBodyRubyComponentMetrics(value: final old),
    ForumBodyRubyComponentMetrics(:final value),
  ) =>
    ForumBodyRubyAtomMetrics.segment(old.alignedTo(value.level)),
  _ => throw StateError('Changed root kind'),
});

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

  ForumBodyRubyTreeEmphasisFormatPreparation open(
    ForumBodyRubyGlyphTreeMetrics metrics, {
    TextScaler scaler = TextScaler.noScaling,
    ForumBodyParagraphCache? targetCache,
    void Function()? owner,
    Iterable<ForumBodyNativeParagraphLease> Function()? prefix,
  }) => ForumBodyRubyTreeEmphasisFormatPreparation(
    glyphMetrics: metrics,
    cache: targetCache ?? cache,
    expectedTextScaler: scaler,
    ensureOwner: owner ?? () {},
    additionalOwnedLeases: prefix,
  );

  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Curve()]) {
      for (final (index, html) in [
        rubyTreeEmphasisSceneNested,
        rubyTreeEmphasisSceneMixed,
        rubyTreeEmphasisSceneSegment,
        '<ruby style="text-emphasis:circle">.<rt>x</rt></ruby>',
      ].indexed) {
        test(
          'fresh format regenerates actual aligned hierarchy fixture=$index $direction $scaler',
          () {
            ForumBodyRubyGlyphTreeMetrics measure(String h) =>
                rubyGlyphTreeMetricsFixture(
                  h,
                  cache,
                  direction: direction,
                  scaler: scaler,
                );
            final original = measure(html),
                previous = _finish(open(original, scaler: scaler));
            final neighbor = measure(
              html
                  .replaceAll(RegExp(r'font-size:[0-9]+px'), 'font-size:40px')
                  .replaceAll('<rt>', '<rt style="font-size:40px">')
                  .replaceAll('<rt style="', '<rt style="font-size:40px;'),
            );
            final aligned = _align(original, neighbor),
                work = open(aligned, scaler: scaler);
            final current = _finish(work, quantum: index + 1);
            final metrics = current.placement.input.input,
                old = previous.placement.input.input;
            expect(metrics.geometry.metrics, same(aligned));
            expect(metrics.geometry, isNot(same(old.geometry)));
            expect(metrics.emptyFonts.bands, isNot(same(old.emptyFonts.bands)));
            expect(current.placement, isNot(same(previous.placement)));
            expect(aligned.input, same(original.input));
            for (final source in original.input.sources) {
              expect(
                metrics.geometry.sourceForId(source.id).source,
                same(source),
              );
            }
            expect(
              current.placement.marks.length,
              previous.placement.marks.length,
            );
            for (final (i, placed) in current.placement.marks.indexed) {
              final id = placed.source.source.source.id;
              expect(
                placed.source.source,
                same(metrics.geometry.sourceForId(id)),
              );
              expect(
                placed.source.line.input,
                same(original.input.sourceForId(id).emphasis),
              );
              expect(
                current.markerPictureInput!.commands[i].nativeInputIdentity,
                previous.markerPictureInput!.commands[i].nativeInputIdentity,
              );
              expect(
                current.frame.childBounds.expandToInclude(placed.fontBounds),
                current.frame.childBounds,
              );
            }
            if (index == 3) {
              expect(current.placement.marks, isEmpty);
              expect(current.markerPictureInput, isNull);
            } else {
              expect(
                aligned.box.bounds.height,
                greaterThan(original.box.bounds.height),
              );
              expect(
                current.markerPictureInput,
                isNot(previous.markerPictureInput),
              );
            }
            final scene = ForumBodyRubyTreeEmphasisScenePreparation(
              input: original.input,
              plan: current,
              cache: cache,
              ensureOwner: () {},
              width: original.input.maxWidth,
              expectedTextScaler: scaler,
            );
            try {
              while (!scene.isReady) {
                scene.advance(maxParts: 1);
              }
              final layout = scene.takeLayout();
              try {
                expect(layout.size, current.frame.size);
                for (final placed in current.placement.marks) {
                  final hit = layout.sourceAt(
                    placed.fontBounds.center + layout.contentOffset,
                  );
                  expect(
                    hit.content,
                    same(original.input.sourceForId(hit.nodeIndex).content),
                  );
                  expect(hit.position.isExact, isFalse);
                }
              } finally {
                layout.close();
              }
            } finally {
              scene.close();
            }
            expect(cache.activeLeases, 0);
          },
        );
      }
    }
  }
  test('actual shared band requests survive complete cooperative planning', () {
    final metrics = rubyGlyphTreeMetricsFixture(
      rubyTreeEmphasisSceneSegment,
      cache,
      scaler: const _Curve(),
      mapInput: (input) {
        final bases = input.sources
            .where(
              (s) =>
                  s.needsNative &&
                  ['A', 'B'].contains(s.glyphs.projection.text),
            )
            .toList();
        final band = ForumBodyTextBandContent(
          contexts: bases.map((s) => s.glyphs).toList(),
        );
        return input.mapGlyphRequests((request) {
          final i = band.contexts.indexOf(request.content);
          return i < 0
              ? request
              : ForumBodyTextRequest.bandChild(band: band, childIndex: i);
        });
      },
    );
    final plan = _finish(open(metrics, scaler: const _Curve()), quantum: 32);
    final sources = plan.placement.input.input.sources
        .where(
          (s) => ['A', 'B'].contains(s.source.source.glyphs.projection.text),
        )
        .toList();
    expect(sources, hasLength(2));
    expect(
      sources.first.line.baseRequest,
      same(metrics.input.requestForSource(sources.first.source.source.id)),
    );
    expect(
      sources.first.line.nativeFootprint.first.request,
      isA<ForumBodyTextBandChildRequest>(),
    );
    expect(cache.activeLeases, 0);
  });
  test(
    'cold cached-only miss resumes and warm planning creates no native work',
    () {
      final metrics = rubyGlyphTreeMetricsFixture(
        rubyTreeEmphasisSceneNested,
        cache,
      );
      cache.clearUnpinned();
      final work = open(metrics),
          before = (cache.layoutBuildCount, cache.pictureBuildCount);
      for (var n = 0; !work.cacheMiss; n++) {
        expect(n, lessThan(30000));
        final step = work.advance(maxParts: 1, cachedOnly: true);
        expect(step.layoutsBuilt + step.picturesBuilt, 0);
      }
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      final first = _finish(work),
          warmBefore = (cache.layoutBuildCount, cache.pictureBuildCount);
      final warm = _finish(open(metrics), cachedOnly: true, quantum: 32);
      expect(warm.markerPictureInput, first.markerPictureInput);
      expect((cache.layoutBuildCount, cache.pictureBuildCount), warmBefore);
    },
  );
  for (final owned in [false, true]) {
    test(
      'same format respects actual external/owned pin pressure owned=$owned',
      () {
        final metrics = rubyGlyphTreeMetricsFixture(_simple, cache);
        final small = ForumBodyParagraphCache(
          maxEntries: 2,
          maxEstimatedBytes: 1 << 24,
        );
        final source = metrics.input.sources.first.glyphs;
        final pin = small.acquire(
          content: ForumBodyParagraphContent.anonymousInline(
            identity: source.identity,
            fontRevision: source.fontRevision,
            styleRevision: source.styleRevision,
            style: source.style,
          ),
          width: 500,
        );
        final work = open(
          metrics,
          targetCache: small,
          prefix: owned ? () => [pin] : null,
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
              expect(n, lessThan(30000));
              if (work.advance(maxParts: 1).waitingForLayoutBudget) break;
            }
            final held = work.nativeLeases.toList(),
                before = (small.layoutBuildCount, small.pictureBuildCount);
            final step = work.advance(maxParts: 32);
            expect(step.waitingForLayoutBudget, isTrue);
            expect(step.formatUnitsPrepared, 0);
            expect(work.nativeLeases, orderedEquals(held));
            expect((small.layoutBuildCount, small.pictureBuildCount), before);
            pin.release();
            final result = _finish(work);
            expect(
              result.placement.input.input.geometry.metrics,
              same(metrics),
            );
          }
        } finally {
          work.close();
          pin.release();
          expect(small.activeLeases, 0);
          small.close();
        }
      },
    );
  }
  test(
    'cancel at every child stage boundary and final publication releases temporary fonts',
    () {
      final metrics = rubyGlyphTreeMetricsFixture(
        '<ruby style="text-emphasis:circle">A<rt style="font-size:24px"></rt></ruby>',
        cache,
      );
      var total = 0;
      _finish(open(metrics), onParts: (n) => total += n);
      for (var boundary = 0; boundary <= total; boundary++) {
        final work = open(metrics);
        for (var n = 0; n < boundary && !work.isReady; n++) {
          work.advance(maxParts: 1);
        }
        work.close();
        expect(work.nativeLeases, isEmpty);
        expect(cache.activeLeases, 0, reason: 'boundary=$boundary');
        expect(() => work.takePlan(), throwsStateError);
      }
    },
  );
  test('stale measured scaling fails before native font acquisition', () {
    final metrics = rubyGlyphTreeMetricsFixture(
      rubyTreeEmphasisSceneNested,
      cache,
    );
    cache.clearUnpinned();
    final before = (cache.layoutBuildCount, cache.pictureBuildCount);
    expect(
      () => _finish(open(metrics, scaler: TextScaler.linear(1.2))),
      throwsArgumentError,
    );
    expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
  });
  test(
    'caught reentry preserves outer work and a returned plan is pure after cache close',
    () {
      final metrics = rubyGlyphTreeMetricsFixture(
        rubyTreeEmphasisSceneMixed,
        cache,
      );
      ForumBodyRubyTreeEmphasisFormatPreparation? work;
      var reentered = false;
      work = open(
        metrics,
        owner: () {
          if (!reentered) {
            reentered = true;
            expect(() => work!.advance(), throwsStateError);
          }
        },
      );
      final plan = _finish(work);
      cache.close();
      expect(reentered, isTrue);
      expect(plan.placement.input.input.geometry.metrics, same(metrics));
      expect(plan.markerPictureInput, isNotNull);
      expect(plan.frame.size.width.isFinite, isTrue);
    },
  );
  test(
    'owner retirement between ready and transfer discards the pure result',
    () {
      final metrics = rubyGlyphTreeMetricsFixture(_simple, cache);
      var active = true;
      final work = open(
        metrics,
        owner: () {
          if (!active) throw StateError('retired');
        },
      );
      while (!work.isReady) {
        work.advance(maxParts: 1);
      }
      active = false;
      expect(() => work.takePlan(), throwsStateError);
      expect(work.isReady, isFalse);
      expect(work.nativeLeases, isEmpty);
      expect(cache.activeLeases, 0);
    },
  );
}
