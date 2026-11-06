import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/src/style/forum_body_text_background_geometry.dart';

const _extent = 36;

Future<Uint8List> _render(
  List<Rect> rectangles,
  double radius, {
  Rect? clip,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (clip != null) canvas.clipRect(clip, doAntiAlias: false);
  ForumBodyTextBackgroundGeometry(
    rectangles,
  ).paint(canvas, Paint()..color = const Color(0x8000ff00), radius);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(_extent, _extent);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

int _alpha(Uint8List pixels, int x, int y) => pixels[4 * (y * _extent + x) + 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rounds the outer contour of touching and overlapping rectangles',
    () async {
      final actual = await _render(const [
        Rect.fromLTRB(2, 2, 18, 16),
        Rect.fromLTRB(18, 2, 32, 16),
        Rect.fromLTRB(12, 2, 22, 16),
      ], 5);
      final single = await _render(const [Rect.fromLTRB(2, 2, 32, 16)], 5);
      expect(actual, orderedEquals(single));
      expect(_alpha(actual, 2, 2), 0);
      expect(_alpha(actual, 18, 2), 128);
      expect(_alpha(actual, 16, 8), 128);
    },
  );

  test(
    'preserves a hole, indentation, and a separately rounded point contact',
    () async {
      const rectangles = [
        Rect.fromLTRB(2, 2, 24, 8),
        Rect.fromLTRB(2, 8, 8, 18),
        Rect.fromLTRB(18, 8, 24, 18),
        Rect.fromLTRB(2, 18, 24, 24),
        Rect.fromLTRB(8, 24, 24, 32),
        Rect.fromLTRB(24, 32, 34, 36),
      ];
      final square = await _render(rectangles, 0);
      for (var y = 0; y < _extent; y++) {
        for (var x = 0; x < _extent; x++) {
          final covered = rectangles.any(
            (rect) => rect.contains(Offset(x + .5, y + .5)),
          );
          expect(_alpha(square, x, y), covered ? 128 : 0, reason: 'at $x,$y');
        }
      }
      final rounded = await _render(rectangles, 20);
      expect(_alpha(rounded, 2, 2), 0);
      expect(_alpha(rounded, 11, 12), 0); // Hole.
      expect(_alpha(rounded, 5, 28), 0); // Indent on the next line.
      expect(_alpha(rounded, 10, 24), 128); // Inside the concave turn.
      expect(_alpha(rounded, 24, 32), lessThan(128));
      expect(_alpha(rounded, 29, 34), 128);
    },
  );

  test(
    'viewport clips through the natural outline without rounding the cut',
    () async {
      final pixels = await _render(
        const [Rect.fromLTRB(2, -16, 30, 12), Rect.fromLTRB(2, 12, 30, 48)],
        8,
        clip: const Rect.fromLTRB(5, 4, 32, 26),
      );
      expect(_alpha(pixels, 5, 4), 128);
      expect(_alpha(pixels, 5, 25), 128);
      expect(_alpha(pixels, 29, 25), 128);
      expect(_alpha(pixels, 4, 4), 0);
      expect(_alpha(pixels, 5, 26), 0);
    },
  );
}
