import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_paper_geometry.dart';

void main() {
  test('the flat endpoint preserves front UVs and has no back face', () {
    final geometry = NovelReaderPaperGeometry(
      size: const Size(320, 480),
      progress: 0,
      touchY: 0.1,
    );
    expect(geometry.back.isEmpty, isTrue);
    expect(geometry.front.positions.length, geometry.front.uv.length);
    for (var i = 0; i < geometry.front.positions.length; i++) {
      expect(geometry.front.positions[i], closeTo(geometry.front.uv[i], 0.001));
    }
  });

  test(
    'a middle fold deforms real texture coordinates and reverses the back',
    () {
      final geometry = NovelReaderPaperGeometry(
        size: const Size(320, 480),
        progress: 0.5,
        touchY: 0.5,
      );
      expect(geometry.front.isEmpty, isFalse);
      expect(geometry.back.isEmpty, isFalse);
      expect(
        geometry.back.positions[geometry.back.positions.length - 2],
        lessThan(geometry.back.positions.first),
      );
      expect(
        geometry.back.uv[geometry.back.uv.length - 2],
        greaterThan(geometry.back.uv.first),
      );
      expect(
        [
          for (var i = 0; i < geometry.front.positions.length; i++)
            (geometry.front.positions[i] - geometry.front.uv[i]).abs(),
        ].reduce((a, b) => a > b ? a : b),
        greaterThan(5),
      );
    },
  );

  test(
    'contact height changes the fold instead of translating a fixed mask',
    () {
      final upper = NovelReaderPaperGeometry(
        size: const Size(320, 640),
        progress: 0.4,
        touchY: 0.1,
      );
      final lower = NovelReaderPaperGeometry(
        size: const Size(320, 640),
        progress: 0.4,
        touchY: 0.9,
      );
      expect(
        upper.front.positions,
        isNot(orderedEquals(lower.front.positions)),
      );
      expect(upper.back.positions, isNot(orderedEquals(lower.back.positions)));
    },
  );

  test('corner, portrait, landscape and near-endpoint meshes stay bounded and finite', () {
    for (final size in [
      const Size(320, 640),
      const Size(800, 400),
      const Size(1, 10000),
    ]) {
      for (final progress in [
        0.0,
        0.000001,
        0.1,
        0.4,
        0.5,
        0.8,
        0.999999,
        1.0,
      ]) {
        for (final touch in [0.0, 0.1, 0.5, 0.9, 1.0]) {
          final g = NovelReaderPaperGeometry(
            size: size,
            progress: progress,
            touchY: touch,
          );
          for (final mesh in [g.front, g.back]) {
            expect(mesh.positions.every((v) => v.isFinite), isTrue);
            expect(
              mesh.indices.every((i) => i < mesh.positions.length ~/ 2),
              isTrue,
            );
            for (var i = 0; i < mesh.uv.length; i += 2) {
              expect(mesh.uv[i], inInclusiveRange(0, size.width));
              expect(mesh.uv[i + 1], inInclusiveRange(0, size.height));
            }
          }
        }
      }
    }
  });
}
