import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
      for (final width in [70.0, 300.0]) {
        for (final (index, html) in mixedEmphasisChildren.indexed) {
          test(
            'source-qualified active parent measurement $index $direction/$scaler/$width',
            () {
              final f = MixedEmphasisParentFixture(
                    html,
                    width: width,
                    direction: direction,
                  ),
                  cache = _cache();
              final value = f
                  .finish(f.open(cache, scaler: scaler), cache)
                  .value;
              addTearDown(value.lease.release);
              expect(value.glyphInput, same(f.text.glyphInput));
              expect(value.plan.content, same(f.input.content));
              expect(value.lease.content, same(f.text.glyphInput.glyphs));
              expect(value.lease.content, same(value.glyphInput.glyphs));
              expect(
                identical(value.lease.content, value.plan.content),
                isFalse,
              );
              expect(value.plan.content.style.textEmphasis.isEnabled, isTrue);
              expect(value.lease.content.style.textEmphasis.isEnabled, isFalse);
              expect(
                value.lease.content.contexts,
                same(value.plan.content.contexts),
              );
              expect(
                value.lease.content.projection,
                same(value.plan.content.projection),
              );
              expect(cache.activeLeases, 1);
              final bands = f.bands(value, cache, scaler: scaler);
              expect(bands.fonts.geometry.targets, hasLength(2));
              expect(bands.fonts.fonts, isNotEmpty);
              for (final (i, atom) in value.plan.rubyAtoms.indexed) {
                expect(
                  bands.children[i]?.source,
                  value.plan.trimmedAtomIndices.contains(i) ? null : same(atom),
                );
                expect(
                  value.lease.layout.dimensions[i].size,
                  value.plan.dimensions[i].size,
                );
              }
              expect(
                () => value.plan.parentRequest.acquire(
                  cache,
                  width: width,
                  textScaler: scaler,
                  cachedOnly: false,
                ),
                throwsA(
                  isA<ForumBodyParagraphLayoutException>().having(
                    (e) => e.failure,
                    'failure',
                    ForumBodyParagraphLayoutFailure.emphasis,
                  ),
                ),
              );
              final before = cache.layoutBuildCount;
              final pending = f.open(cache, scaler: scaler);
              for (var n = 0; !pending.isReady && !pending.cacheMiss; n++) {
                expect(n, lessThan(30000));
                final step = pending.advance(maxParts: 1, cachedOnly: true);
                expect(step.waitingForLayoutBudget, isFalse);
                expect(cache.layoutBuildCount, before);
              }
              // Completed formats deliberately retire some discovery parents.
              // A warm-only miss must pause, then resume this same transaction.
              final warm = f.finish(pending, cache, quantum: 7).value;
              try {
                expect(
                  warm.lease.nativeInputIdentity,
                  value.lease.nativeInputIdentity,
                );
                expect(warm.plan.content, same(value.plan.content));
              } finally {
                warm.lease.release();
              }
              value.lease.release();
              cache.clearUnpinned();
              expect(cache.activeLeases, 0);
              expect(bands.fonts.geometry.input, same(f.text));
            },
          );
        }
      }
    }
  }
  test(
    'equal source values cannot substitute a distinct original/glyph association',
    () {
      final first = MixedEmphasisParentFixture(mixedEmphasisChildren[0]),
          other = MixedEmphasisParentFixture(mixedEmphasisChildren[0]),
          cache = _cache();
      expect(
        () => ForumBodyInlinePlanPreparation.emphasisParent(
          input: first.input,
          glyphInput: other.text.glyphInput,
          cache: cache,
          textScaler: TextScaler.noScaling,
          ensureOwner: () {},
        ),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphInputFailure.identity,
          ),
        ),
      );
      expect(cache.layoutBuildCount, 0);
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'cold warm-only miss retains same work for later native preparation',
    () {
      final f = MixedEmphasisParentFixture(mixedEmphasisChildren[1]),
          cache = _cache();
      final job = f.open(cache);
      for (var n = 0; !job.cacheMiss; n++) {
        expect(n, lessThan(30000));
        final s = job.advance(maxParts: 1, cachedOnly: true);
        expect(s.partsPrepared, lessThanOrEqualTo(1));
        expect(s.waitingForLayoutBudget, isFalse);
      }
      expect(cache.layoutBuildCount, 0);
      expect(cache.activeLeases, 0);
      final ready = f.finish(job, cache).value;
      expect(ready.lease.content, same(f.text.glyphInput.glyphs));
      ready.lease.release();
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'retired owner releases active/ready measurement and cannot transfer',
    () {
      final f = MixedEmphasisParentFixture(mixedEmphasisChildren[2]),
          cache = _cache();
      final initial = f.finish(f.open(cache), cache);
      initial.value.lease.release();
      for (final boundary in {
        0,
        1,
        5,
        initial.parts ~/ 2,
        initial.parts - 1,
        initial.parts,
      }) {
        var active = true;
        final job = f.open(
          cache,
          guard: () {
            if (!active) {
              throw StateError('Retired');
            }
          },
        );
        for (var n = 0; n < boundary; n++) {
          job.advance(maxParts: 1);
        }
        active = false;
        expect(
          job.isReady ? job.takeEmphasisParent : () => job.advance(maxParts: 1),
          throwsStateError,
        );
        job.close();
        expect(cache.activeLeases, 0);
      }
    },
  );
  test('an ordinary plan cannot use the dedicated emphasis transfer', () {
    final f = MixedEmphasisParentFixture(
          mixedEmphasisChildren[0],
          parentStyle: 'line-height:.4',
        ),
        cache = _cache();
    final job = ForumBodyInlinePlanPreparation(
      input: f.input,
      cache: cache,
      textScaler: TextScaler.noScaling,
      ensureOwner: () {},
    );
    try {
      while (!job.isReady) {
        job.advance(maxParts: 1);
      }
      expect(job.takeEmphasisParent, throwsStateError);
      expect(job.isReady, isTrue);
      final value = job.take();
      expect(value.lease.content, same(f.input.content));
      value.lease.release();
      expect(cache.activeLeases, 0);
    } finally {
      job.close();
    }
  });
}
