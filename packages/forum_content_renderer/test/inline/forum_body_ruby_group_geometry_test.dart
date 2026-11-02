import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart'
    show ForumBodyRubyChildMetrics, ForumBodyRubyGroupGeometry;

List<ForumBodyParagraphContent> _contents() {
  final document = const ForumBodyParser().parse(
    html:
        '<p><span style="font-size:20px;color:red">AB</span>'
        '<span style="font-size:10px;color:blue">xy</span>'
        '<span style="font-size:8px;color:green">WXYZAB</span></p>',
    sourceId: 'nested-child-geometry',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  return [
    for (var index = 0; index < 3; index++)
      const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: '0/$index',
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      ),
  ];
}

ForumBodyRubyChildMetrics _capture(ForumBodyTextLease lease) {
  var bounds = Offset.zero & Size(lease.layout.width, lease.layout.height);
  for (final box in lease.layout.selectionBoxes(
    0,
    lease.content.projection.text.length,
  )) {
    bounds = bounds.expandToInclude(box.toRect());
  }
  return ForumBodyRubyChildMetrics(
    bounds: bounds,
    alphabeticBaseline: lease.layout.alphabeticBaseline,
  );
}

Future<List<int>> _pixels(
  void Function(Canvas) paint,
  Size size,
  int ratio,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(ratio.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (size.width * ratio).ceil(),
      (size.height * ratio).ceil(),
    );
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
  for (final innerSide in ForumBodyRubySide.values) {
    for (final outerSide in ForumBodyRubySide.values) {
      for (final nestedBase in [false, true]) {
        for (final ratio in [1, 3]) {
          test(
            'composite nested child paints with the shared stack, inner=$innerSide outer=$outerSide base=$nestedBase DPR$ratio',
            () async {
              final contents = _contents();
              final cache = ForumBodyParagraphCache(
                maxEntries: 4,
                maxEstimatedBytes: 1 << 20,
              );
              addTearDown(cache.close);
              final inner = ForumBodyRubyGroupLayout.create(
                cache: cache,
                base: contents[0],
                annotation: contents[1],
                side: innerSide,
              );
              final outerText = cache.acquire(content: contents[2], width: 256);
              final innerBox = ForumBodyRubyChildMetrics(
                bounds: Offset.zero & inner.size,
                alphabeticBaseline: inner.baseline,
              );
              final textBox = _capture(outerText);
              final geometry = ForumBodyRubyGroupGeometry(
                annotations: [(hasAnnotation: true, gap: 0.0, side: outerSide)],
              );
              addTearDown(geometry.close);
              geometry.addBase(nestedBase ? innerBox : textBox);
              geometry.addAnnotation(nestedBase ? textBox : innerBox);
              final counts = (
                cache.layoutBuildCount,
                cache.pictureBuildCount,
                cache.activeLeases,
              );
              expect(geometry.advance(maxParts: 1), 1);
              expect(geometry.isReady, true);
              final result = geometry.takeMetrics();
              expect((
                cache.layoutBuildCount,
                cache.pictureBuildCount,
                cache.activeLeases,
              ), counts);
              expect(result.size, const Size(48, 38));
              final over = outerSide == ForumBodyRubySide.over;
              final innerOver = innerSide == ForumBodyRubySide.over;
              final innerOrigin = Offset(
                4,
                nestedBase ? (over ? 8 : 0) : (over ? 0 : 8),
              );
              final outerOrigin = Offset(
                0,
                nestedBase ? (over ? 0 : 30) : (over ? 30 : 0),
              );
              expect(result.baseOffset, nestedBase ? innerOrigin : outerOrigin);
              expect(
                result.annotationOffset,
                nestedBase ? outerOrigin : innerOrigin,
              );
              final painters = [
                for (final content in contents)
                  TextPainter(
                    text: content.textSpan,
                    textDirection: TextDirection.ltr,
                  )..layout(),
              ];
              try {
                final actual = await _pixels(
                  (canvas) {
                    inner.paint(
                      canvas,
                      nestedBase ? result.baseOffset : result.annotationOffset,
                    );
                    outerText.layout.paint(
                      canvas,
                      nestedBase ? result.annotationOffset : result.baseOffset,
                    );
                  },
                  result.size,
                  ratio,
                );
                final expected = await _pixels(
                  (canvas) {
                    painters[0].paint(
                      canvas,
                      innerOrigin + Offset(0, innerOver ? 10 : 0),
                    );
                    painters[1].paint(
                      canvas,
                      innerOrigin + Offset(10, innerOver ? 0 : 20),
                    );
                    painters[2].paint(canvas, outerOrigin);
                  },
                  const Size(48, 38),
                  ratio,
                );
                expect(actual, expected);
              } finally {
                for (final painter in painters) {
                  painter.dispose();
                }
                inner.close();
                outerText.release();
              }
              expect(cache.activeLeases, 0);
            },
          );
        }
      }
    }
  }
  test(
    'many composite ranks yield by rank and freeze topology and results',
    () {
      final inputs = [
        for (var index = 0; index < 101; index++)
          (
            hasAnnotation: index.isEven,
            gap: 1.0,
            side: index.isEven
                ? ForumBodyRubySide.over
                : ForumBodyRubySide.under,
          ),
      ];
      final geometry = ForumBodyRubyGroupGeometry(annotations: inputs);
      addTearDown(geometry.close);
      inputs.clear();
      geometry.addBase(
        ForumBodyRubyChildMetrics(
          bounds: const Rect.fromLTWH(-2, -3, 24, 25),
          alphabeticBaseline: 16,
        ),
      );
      for (var index = 0; index < 101; index++) {
        geometry.addAnnotation(
          index.isEven
              ? ForumBodyRubyChildMetrics(
                  bounds: const Rect.fromLTWH(-1, -2, 12, 7),
                  alphabeticBaseline: 3,
                )
              : null,
        );
      }
      expect(geometry.isMeasured, true);
      expect(() => geometry.takeMetrics(), throwsStateError);
      for (var rank = 0; rank < 101; rank++) {
        expect(geometry.advance(maxParts: 1), 1);
        expect(geometry.positionedAnnotations, rank + 1);
        expect(geometry.isReady, rank == 100);
      }
      final result = geometry.takeMetrics();
      expect(result.annotations, hasLength(101));
      expect(result.baseOffset.dx, 2);
      expect(result.baseOffset.dy, result.baseline - 16);
      expect(result.annotations.where((a) => a.hasAnnotation), hasLength(51));
      expect(() => result.annotations.clear(), throwsUnsupportedError);
      expect(() => geometry.advance(maxParts: 1), throwsStateError);
      geometry.close();
      expect(result.annotations, hasLength(101));
    },
  );
  test(
    'numeric capture survives owner retirement without becoming paint proof',
    () {
      final contents = _contents();
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      final base = cache.acquire(content: contents[0], width: 100);
      final annotation = cache.acquire(content: contents[1], width: 100);
      final geometry = ForumBodyRubyGroupGeometry(
        annotations: [
          (hasAnnotation: true, gap: 0.0, side: ForumBodyRubySide.over),
        ],
      );
      addTearDown(geometry.close);
      geometry.addBase(_capture(base));
      geometry.addAnnotation(_capture(annotation));
      cache.close();
      expect(base.isActive, false);
      expect(annotation.isActive, false);
      expect(cache.activeLeases, 0);
      expect(geometry.advance(maxParts: 1), 1);
      final numbers = geometry.takeMetrics();
      expect(numbers.size, const Size(40, 30));
      expect(() => base.layout, throwsStateError);
      expect(() => annotation.layout, throwsStateError);
      base.release();
      annotation.release();
      expect(cache.estimatedRetainedBytes, 0);
    },
  );
  test(
    'geometry rejects invalid boxes, missing ranks and incompatible row targets',
    () {
      expect(
        () => ForumBodyRubyChildMetrics(
          bounds: const Rect.fromLTRB(4, 0, 2, 1),
          alphabeticBaseline: 0,
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(
        () => ForumBodyRubyChildMetrics(
          bounds: const Rect.fromLTWH(0, 0, 1, 1),
          alphabeticBaseline: double.nan,
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      final geometry = ForumBodyRubyGroupGeometry(
        annotations: [
          (hasAnnotation: false, gap: 3.0, side: ForumBodyRubySide.over),
          (hasAnnotation: true, gap: 0.0, side: ForumBodyRubySide.under),
        ],
      );
      addTearDown(geometry.close);
      final child = ForumBodyRubyChildMetrics(
        bounds: const Rect.fromLTWH(0, 0, 10, 10),
        alphabeticBaseline: 8,
      );
      expect(() => geometry.addAnnotation(null), throwsStateError);
      geometry.addBase(child);
      expect(
        () => geometry.addAnnotation(child),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      geometry.addAnnotation(null);
      expect(
        () => geometry.addAnnotation(null),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      geometry.addAnnotation(child);
      geometry.advance(maxParts: 2);
      final result = geometry.takeMetrics();
      expect(result.size, const Size(10, 20));
      final target = ForumBodyRubyLevelMetrics.single(result);
      expect(
        () => ForumBodyRubyGroupGeometry(
          annotations: [
            (hasAnnotation: true, gap: 0.0, side: ForumBodyRubySide.over),
          ],
          level: target,
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
    },
  );
}
