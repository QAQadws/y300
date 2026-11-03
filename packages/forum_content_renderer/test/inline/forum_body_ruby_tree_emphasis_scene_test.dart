import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_tree_emphasis_scene_fixture.dart';

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 20 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

Future<List<int>> _pixels(void Function(Canvas) paint, int dpr) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(dpr.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(300 * dpr, 240 * dpr);
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

ForumBodyRubyGlyphTreeBinding _glyphs(RubyTreeEmphasisSceneFixture f) {
  final work = ForumBodyRubyGlyphTreeBindingPreparation(
    geometry: f.plan.placement.input.input.geometry,
    cache: f.cache,
    ensureOwner: () {},
    expectedTextScaler: f.scaler,
  );
  try {
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    return work.takeBinding();
  } finally {
    work.close();
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
    for (final nonlinear in [false, true]) {
      for (final (fixture, html) in [
        rubyTreeEmphasisSceneNested,
        rubyTreeEmphasisSceneMixed,
        rubyTreeEmphasisSceneSegment,
      ].indexed) {
        test(
          'complete current-source tree scene fixture=$fixture $direction nonlinear=$nonlinear',
          () {
            final f = RubyTreeEmphasisSceneFixture(
              html,
              direction: direction,
              scaler: nonlinear ? const _Curve() : TextScaler.noScaling,
            );
            final layout = f.finish(f.open()),
                geometry = f.plan.placement.input.input.geometry;
            try {
              expect(layout.isOwnedBy(f.cache), isTrue);
              expect(layout.nativeLeases.length, f.plan.retainedHandleCount);
              expect(f.cache.activeLeases, f.plan.retainedHandleCount);
              expect(layout.plan, same(f.plan));
              expect(
                (layout.size, layout.baseline, layout.contentOffset),
                (
                  f.plan.frame.size,
                  f.plan.frame.baseline,
                  f.plan.frame.childOffset,
                ),
              );
              expect(
                layout.sources.map((s) => s.source),
                orderedEquals(f.input.sources),
              );
              for (final placed in f.plan.placement.marks) {
                final hit = layout.sourceAt(
                  placed.fontBounds.center + layout.contentOffset,
                );
                expect(hit.nodeIndex, placed.source.source.source.id);
                expect(hit.content, same(placed.source.source.source.content));
                expect(hit.position.isExact, isFalse);
                final unit =
                    placed.source.line.input.units[placed.mark.unitIndex];
                expect(
                  hit.position.sourceRune,
                  hit.content.projection
                      .sourceAtUtf16(unit.governingUtf16)
                      .sourceRune,
                );
              }
              for (final bound in layout.sources) {
                final source = bound.source;
                expect(bound.position, same(geometry.sourceForId(source.id)));
                expect(layout.sourceForId(source.id), same(bound));
                final boxes = layout.selectionBoxes(
                  sourceId: source.id,
                  startUtf16: 0,
                  endUtf16: source.content.projection.text.length,
                  paintedOnly: true,
                );
                if (source.needsNative) {
                  final lease = f.input
                      .requestForSource(source.id)
                      .acquire(
                        f.cache,
                        width: 500,
                        textScaler: f.scaler,
                        cachedOnly: true,
                      )!;
                  try {
                    final origin =
                        bound.position.contextOrigin + layout.contentOffset;
                    expect(
                      boxes.map((b) => b.toRect()),
                      lease.layout
                          .selectionBoxes(
                            0,
                            source.content.projection.text.length,
                          )
                          .map(
                            (b) => b
                                .toRect()
                                .shift(bound.position.contextOrigin)
                                .shift(layout.contentOffset),
                          ),
                    );
                    expect(
                      bound.glyphNativeInputIdentity,
                      lease.nativeInputIdentity,
                    );
                    expect(origin.dx.isFinite, isTrue);
                  } finally {
                    lease.release();
                  }
                }
                for (final box in boxes.where((b) => b.toRect().width > 1e-6)) {
                  final hit = layout.sourceAt(box.toRect().center);
                  // Collapsed rows can overlap; whichever real glyph/mark wins
                  // must return its original current source, never glyph styles.
                  expect(
                    hit.content,
                    same(f.input.sourceForId(hit.nodeIndex).content),
                  );
                }
              }
              if (fixture == 1) {
                expect(layout.sources.any((s) => s.usesInlineParent), isTrue);
              }
              expect(() => layout.backgrounds.clear(), throwsUnsupportedError);
              expect(() => layout.sources.clear(), throwsUnsupportedError);
              expect(
                () => layout.sourceAt(const Offset(double.nan, 0)),
                throwsArgumentError,
              );
            } finally {
              layout.close();
            }
            expect(layout.isActive, isFalse);
            expect(layout.nativeLeases, isEmpty);
          },
        );
      }
    }
  }
  for (final dpr in [1, 3]) {
    for (final (fixture, html) in [
      rubyTreeEmphasisSceneNested,
      rubyTreeEmphasisSceneMixed,
    ].indexed) {
      test(
        'full tree, separate alpha backgrounds and native marker transforms fixture=$fixture DPR$dpr',
        () async {
          final f = RubyTreeEmphasisSceneFixture(
            html,
            scaler: TextScaler.linear(1.3),
          );
          final layout = f.finish(f.open()), reference = _glyphs(f);
          final marks = <Object, ForumBodyEmphasisMarkLease>{};
          try {
            for (final placed in f.plan.placement.marks) {
              final font = ForumBodyEmphasisMarkRequest(placed.mark.input)
                  .acquire(
                    f.cache,
                    width: 500,
                    textScaler: f.scaler,
                    cachedOnly: true,
                  )!;
              final key = font.nativeInputIdentity;
              if (marks.containsKey(key)) {
                font.release();
              } else {
                marks[key] = font;
              }
            }
            const offset = Offset(12.3, 17.7),
                clip = Rect.fromLTWH(0, 0, 300, 240);
            final counters = (
              f.cache.layoutBuildCount,
              f.cache.pictureBuildCount,
            );
            final actual = await _pixels((canvas) {
              layout.paintBackgrounds(canvas, offset, clip: clip);
              layout.paint(canvas, offset);
            }, dpr);
            final expected = await _pixels((canvas) {
              canvas.save();
              canvas.clipRect(clip);
              for (final surface in reference.backgrounds) {
                canvas.drawRect(
                  surface.rect.shift(layout.contentOffset).shift(offset),
                  Paint()..color = surface.font.background.color,
                );
              }
              canvas.restore();
              canvas.save();
              canvas.translate(offset.dx, offset.dy);
              canvas.translate(
                layout.contentOffset.dx,
                layout.contentOffset.dy,
              );
              reference.paintGlyphs(canvas, Offset.zero);
              for (final placed in f.plan.placement.marks) {
                final font = marks.values.firstWhere(
                  (font) =>
                      identical(font.input, placed.mark.input) ||
                      font.input == placed.mark.input,
                );
                canvas.save();
                canvas.translate(
                  placed.baselineOrigin.dx,
                  placed.baselineOrigin.dy,
                );
                if (placed.mark.fitScale != 1) {
                  canvas.translate(placed.fontOffset.dx, placed.fontOffset.dy);
                  canvas.scale(placed.mark.fitScale, placed.mark.fitScale);
                  font.layout.paint(canvas, Offset.zero);
                } else {
                  font.layout.paint(canvas, placed.fontOffset);
                }
                canvas.restore();
              }
              canvas.restore();
            }, dpr);
            expect(actual, expected);
            expect(actual.any((byte) => byte > 0), isTrue);
            expect((
              f.cache.layoutBuildCount,
              f.cache.pictureBuildCount,
            ), counters);
          } finally {
            for (final font in marks.values) {
              font.release();
            }
            reference.close();
            layout.close();
          }
        },
      );
    }
  }
  test(
    'shared band keys remain actual aliases while source and final scene stay distinct',
    () {
      final f = RubyTreeEmphasisSceneFixture(
        rubyTreeEmphasisSceneSegment,
        mapInput: (input) {
          final sources = input.sources
              .where((s) => ['A', 'B'].contains(s.glyphs.projection.text))
              .toList();
          final band = ForumBodyTextBandContent(
            contexts: sources.map((s) => s.glyphs).toList(),
          );
          return input.mapGlyphRequests((request) {
            final index = band.contexts.indexOf(request.content);
            return index < 0
                ? request
                : ForumBodyTextRequest.bandChild(band: band, childIndex: index);
          });
        },
      );
      final layout = f.finish(f.open());
      try {
        final bases = layout.sources
            .where((s) => ['A', 'B'].contains(s.source.content.projection.text))
            .toList();
        expect(
          bases.first.glyphNativeInputIdentity,
          bases.last.glyphNativeInputIdentity,
        );
        expect(
          bases.first.source.content,
          isNot(same(bases.last.source.content)),
        );
        expect(layout.nativeLeases.length, f.plan.retainedHandleCount);
      } finally {
        layout.close();
      }
    },
  );
  test(
    'zero targets retain original glyph geometry and no marker scene slot',
    () {
      for (final html in [
        '<ruby>AB<rt>x</rt></ruby>',
        '<ruby style="text-emphasis:circle">.<rt>x</rt></ruby>',
        '<ruby style="text-emphasis:circle"><rb></rb><rt></rt></ruby>',
      ]) {
        final f = RubyTreeEmphasisSceneFixture(html),
            layout = f.finish(f.open());
        try {
          expect(f.plan.markerPictureInput, isNull);
          expect(layout.contentOffset, Offset.zero);
          expect(
            layout.nativeLeases.length,
            f.plan.placement.input.input.geometry.metrics.glyphHandleCount,
          );
          for (final source in layout.sources.where(
            (s) => s.source.content.isSourceFree,
          )) {
            final hit = layout.sourceAt(source.position.contextOrigin);
            expect(hit.position.isExact, isFalse);
          }
        } finally {
          layout.close();
        }
      }
    },
  );
}
