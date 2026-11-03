import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_tree_emphasis_scene_fixture.dart';

const _simple = '<ruby style="text-emphasis:circle">AB<rt>x</rt></ruby>';

final class _ScaleAccess {
  bool forbidden = false;
}

final class _Curve extends TextScaler {
  _Curve({this.overrides = const {}});
  final Map<double, double> overrides;
  final access = _ScaleAccess();
  @override
  double scale(double size) {
    if (access.forbidden) {
      throw StateError('Caller scaler retained after freeze');
    }
    return overrides[size] ?? size * (size < 20 ? 1.4 : 1.1);
  }

  @override
  double get textScaleFactor =>
      throw StateError('Sample actual full/half fonts');
}

void _paint(ForumBodyRubyTreeEmphasisLayout layout) {
  final recorder = ui.PictureRecorder();
  try {
    layout.paint(Canvas(recorder), const Offset(12.3, 17.7));
  } finally {
    recorder.endRecording().dispose();
  }
}

ForumBodyParagraphLease _pin(
  RubyTreeEmphasisSceneFixture f,
  ForumBodyParagraphCache cache,
) {
  final source = f.input.sources.first.glyphs;
  return cache.acquire(
    content: ForumBodyParagraphContent.anonymousInline(
      identity: source.identity,
      fontRevision: source.fontRevision,
      styleRevision: source.styleRevision,
      style: source.style,
    ),
    width: 500,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  test(
    'different original graphs, request mappings and widths cannot borrow a measured scene',
    () {
      final f = RubyTreeEmphasisSceneFixture(_simple),
          foreign = RubyTreeEmphasisSceneFixture(_simple);
      final before = (
        f.cache.layoutBuildCount,
        f.cache.pictureBuildCount,
        f.cache.activeLeases,
      );
      expect(
        () => f.open(currentInput: foreign.input),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(
        () => f.open(currentInput: f.input.mapGlyphRequests((r) => r)),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(
        () => f.open(width: 501),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(
        () => f.open(width: double.nan),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect((
        f.cache.layoutBuildCount,
        f.cache.pictureBuildCount,
        f.cache.activeLeases,
      ), before);
    },
  );
  test(
    'glyph, half-font and empty-RT scale changes fail before any native acquisition',
    () {
      final f = RubyTreeEmphasisSceneFixture(
        '<ruby style="text-emphasis:circle">A<rt style="font-size:24px"></rt></ruby>',
        scaler: _Curve(),
      );
      f.cache.clearUnpinned();
      for (final scaler in [
        TextScaler.linear(2),
        _Curve(overrides: {10: 9}),
        _Curve(overrides: {24: 24}),
        _Curve(overrides: {20: double.nan}),
      ]) {
        final before = (f.cache.layoutBuildCount, f.cache.pictureBuildCount);
        expect(
          () => f.finish(f.open(expectedScaler: scaler)),
          throwsA(
            isA<ForumBodyParagraphLayoutException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphLayoutFailure.scale,
            ),
          ),
        );
        expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), before);
        expect(f.cache.activeLeases, 0);
      }
    },
  );
  test(
    'all raw scaling freezes before native work and nested binders use the immutable snapshot',
    () {
      final f = RubyTreeEmphasisSceneFixture(
        rubyTreeEmphasisSceneNested,
        scaler: _Curve(),
      );
      f.cache.clearUnpinned();
      final before = f.cache.layoutBuildCount, raw = _Curve();
      final layout = f.finish(
        f.open(
          expectedScaler: raw,
          owner: () {
            if (f.cache.layoutBuildCount > before) raw.access.forbidden = true;
          },
        ),
      );
      try {
        expect(raw.access.forbidden, isTrue);
        _paint(layout);
      } finally {
        layout.close();
      }
    },
  );
  test(
    'complete glyph/font/scene footprint rejects before glyph acquisition',
    () {
      final f = RubyTreeEmphasisSceneFixture(_simple),
          small = ForumBodyParagraphCache(
            maxEntries: 3,
            maxEstimatedBytes: 1 << 24,
          );
      try {
        expect(
          () => f.finish(f.open(targetCache: small)),
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
        small.close();
      }
    },
  );
  for (final owned in [false, true]) {
    test(
      'external native pin resumes the same scene while impossible owned prefix fails owned=$owned',
      () {
        final f = RubyTreeEmphasisSceneFixture(_simple),
            small = ForumBodyParagraphCache(
              maxEntries: 4,
              maxEstimatedBytes: 1 << 24,
            );
        final pin = _pin(f, small), before = small.layoutBuildCount;
        final work = f.open(
          targetCache: small,
          prefix: owned ? () => [pin] : null,
        );
        try {
          if (owned) {
            expect(
              () => f.finish(work),
              throwsA(
                isA<ForumBodyParagraphBudgetException>().having(
                  (e) => e.failure,
                  'failure',
                  ForumBodyParagraphBudgetFailure.content,
                ),
              ),
            );
            expect(small.layoutBuildCount, before);
            expect(small.pictureBuildCount, 0);
            expect(pin.isActive, isTrue);
          } else {
            for (var n = 0; ; n++) {
              expect(n, lessThan(40000));
              if (work.advance(maxParts: 1).waitingForLayoutBudget) break;
            }
            final held = work.nativeLeases.toList(),
                counts = (small.layoutBuildCount, small.pictureBuildCount);
            final wait = work.advance();
            expect(wait.partsPrepared, 0);
            expect(wait.waitingForLayoutBudget, isTrue);
            expect(work.nativeLeases, orderedEquals(held));
            expect((small.layoutBuildCount, small.pictureBuildCount), counts);
            pin.release();
            final layout = f.finish(work);
            try {
              expect(layout.nativeLeases.length, f.plan.retainedHandleCount);
              _paint(layout);
            } finally {
              layout.close();
            }
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
    'cached-only cold miss preserves partial glyph work and warm scene builds nothing',
    () {
      final f = RubyTreeEmphasisSceneFixture(rubyTreeEmphasisSceneMixed);
      f.cache.clearUnpinned();
      final counts = (f.cache.layoutBuildCount, f.cache.pictureBuildCount),
          work = f.open();
      for (var n = 0; !work.cacheMiss; n++) {
        expect(n, lessThan(40000));
        final step = work.advance(maxParts: 1, cachedOnly: true);
        expect(step.nativeLayoutsBuilt + step.picturesRecorded, 0);
      }
      expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), counts);
      final first = f.finish(work);
      first.close();
      final built = (f.cache.layoutBuildCount, f.cache.pictureBuildCount);
      final warm = f.finish(f.open(), cachedOnly: true, quantum: 32);
      try {
        _paint(warm);
      } finally {
        warm.close();
      }
      expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), built);
    },
  );
  test(
    'persistent visible owner survives transient preparation retirement including opaque parents',
    () {
      final f = RubyTreeEmphasisSceneFixture(rubyTreeEmphasisSceneMixed);
      var preparing = true, visible = true;
      final layout = f.finish(
        f.open(
          owner: () {
            if (!preparing) throw StateError('Transient preparation retired');
          },
          visibleOwner: () {
            if (!visible) throw StateError('Visible document retired');
          },
        ),
      );
      preparing = false;
      try {
        expect(layout.isActive, isTrue);
        _paint(layout);
        layout.sourceAt(Offset.zero);
        final source = layout.sources.first.source;
        layout.selectionBoxes(
          sourceId: source.id,
          startUtf16: 0,
          endUtf16: source.content.projection.text.length,
        );
        visible = false;
        expect(layout.ensureActive, throwsStateError);
        expect(() => _paint(layout), throwsStateError);
        expect(() => layout.sourceAt(Offset.zero), throwsStateError);
        expect(
          () => layout.selectionBoxes(
            sourceId: source.id,
            startUtf16: 0,
            endUtf16: 0,
          ),
          throwsStateError,
        );
      } finally {
        layout.close();
      }
    },
  );
  test(
    'all work boundaries and final publication release only transaction resources',
    () {
      final f = RubyTreeEmphasisSceneFixture(rubyTreeEmphasisSceneNested),
          counter = f.open();
      var parts = 0;
      while (!counter.isReady) {
        parts += counter.advance(maxParts: 1).partsPrepared;
      }
      counter.close();
      for (var stop = 0; stop <= parts; stop++) {
        f.cache.clearUnpinned();
        var active = true;
        final work = f.open(
          owner: () {
            if (!active) throw StateError('retired');
          },
        );
        for (var n = 0; n < stop; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(work.advance, throwsStateError);
        expect(work.takeLayout, throwsStateError);
        work.close();
        expect(f.cache.activeLeases, 0);
      }
      ForumBodyRubyTreeEmphasisScenePreparation? publish;
      publish = f.open(
        owner: () {
          if (publish?.isReady == true) publish!.close();
        },
      );
      expect(() => f.finish(publish!), throwsStateError);
      expect(f.cache.activeLeases, 0);
    },
  );
  test(
    'caught reentry preserves outer work and cache closure revokes actual layout',
    () {
      final f = RubyTreeEmphasisSceneFixture(_simple);
      ForumBodyRubyTreeEmphasisScenePreparation? work;
      work = f.open(
        owner: () {
          if (work == null) return;
          expect(work.advance, throwsStateError);
          expect(work.takeLayout, throwsStateError);
        },
      );
      final layout = f.finish(work);
      f.cache.close();
      expect(layout.isActive, isFalse);
      expect(layout.isOwnedBy(f.cache), isFalse);
      expect(layout.ensureActive, throwsStateError);
      layout.close();
    },
  );
  test(
    'prefix EOF retirement does not borrow or release the caller prefix',
    () {
      final f = RubyTreeEmphasisSceneFixture(_simple), pin = _pin(f, f.cache);
      ForumBodyRubyTreeEmphasisScenePreparation? work;
      Iterable<ForumBodyNativeParagraphLease> prefix() sync* {
        yield pin;
        work!.close();
      }

      work = f.open(prefix: prefix);
      try {
        expect(() => f.finish(work!), throwsStateError);
        expect(pin.isActive, isTrue);
        expect(f.cache.activeLeases, 1);
      } finally {
        pin.release();
      }
    },
  );
  for (final retireCache in [false, true]) {
    test(
      'native picture creation retirement cannot publish late scene cache=$retireCache',
      () {
        final f = RubyTreeEmphasisSceneFixture(_simple), work = f.open();
        final oldCreate = ui.Picture.onCreate,
            oldDispose = ui.Picture.onDispose;
        var created = 0, disposed = 0;
        ui.Picture.onCreate = (_) {
          created++;
          if (retireCache) {
            f.cache.close();
          } else {
            work.close();
          }
        };
        ui.Picture.onDispose = (_) {
          disposed++;
        };
        try {
          expect(() => f.finish(work), throwsStateError);
        } finally {
          ui.Picture.onCreate = oldCreate;
          ui.Picture.onDispose = oldDispose;
          work.close();
        }
        expect(created, 1);
        expect(disposed, 1);
        expect(f.cache.pictureBuildCount, 0);
        expect(f.cache.activeLeases, 0);
      },
    );
  }
}
