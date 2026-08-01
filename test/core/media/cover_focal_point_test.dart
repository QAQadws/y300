import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/cover_focal_point.dart';

void main() {
  group('CoverFocalPoint', () {
    test('fromNullable returns null when either coord is null', () {
      expect(CoverFocalPoint.fromNullable(null, 0.5), isNull);
      expect(CoverFocalPoint.fromNullable(0.5, null), isNull);
      expect(CoverFocalPoint.fromNullable(null, null), isNull);
    });

    test('fromNullable clamps out-of-range coords', () {
      final focus = CoverFocalPoint.fromNullable(2.0, -3.0);
      expect(focus, isNotNull);
      expect(focus!.x, 1.0);
      expect(focus.y, -1.0);
    });

    test('toAlignment maps coordinates directly to Alignment', () {
      expect(const CoverFocalPoint(0, 0).toAlignment(), Alignment.center);
      expect(const CoverFocalPoint(-1, -1).toAlignment(), Alignment.topLeft);
      expect(const CoverFocalPoint(1, 1).toAlignment(), Alignment.bottomRight);
      expect(
        const CoverFocalPoint(0.5, -0.25).toAlignment(),
        const Alignment(0.5, -0.25),
      );
    });

    test('equality is by value', () {
      expect(const CoverFocalPoint(0.3, 0.7), const CoverFocalPoint(0.3, 0.7));
      expect(
        const CoverFocalPoint(0.3, 0.7),
        isNot(const CoverFocalPoint(0.7, 0.3)),
      );
    });
  });

  group('coverAlignmentFromFocus', () {
    test('falls back to center when focus unset', () {
      expect(coverAlignmentFromFocus(null, null), Alignment.center);
      expect(coverAlignmentFromFocus(0.5, null), Alignment.center);
    });

    test('maps stored focus to Alignment', () {
      expect(coverAlignmentFromFocus(-1.0, 1.0), const Alignment(-1.0, 1.0));
    });

    test('clamps stored focus before mapping', () {
      expect(coverAlignmentFromFocus(5.0, -5.0), const Alignment(1.0, -1.0));
    });
  });
}
