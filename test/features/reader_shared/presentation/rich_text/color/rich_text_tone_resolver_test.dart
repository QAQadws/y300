import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/hct/hct.dart';
import 'package:y300/features/reader_shared/presentation/rich_text/color/rich_text_color_contrast.dart';
import 'package:y300/features/reader_shared/presentation/rich_text/color/rich_text_tone_resolver.dart';

void main() {
  const contrast = FlutterRichTextColorContrast();
  const resolver = MaterialRichTextToneResolver();

  group('MaterialRichTextToneResolver', () {
    test('returns the requested color unchanged when already readable', () {
      const requested = Color(0xFF3366CC);

      final resolved = resolver.resolveReadableForeground(
        requested: requested,
        background: const Color(0xFFFFFFFF),
        fallback: const Color(0xFF000000),
        minimumContrast: 4.5,
      );

      expect(resolved, requested);
    });

    test('returns a final ARGB candidate that reaches 4.5 contrast', () {
      const requested = Color(0xFF999999);
      const background = Color(0xFFFFFFFF);

      final resolved = resolver.resolveReadableForeground(
        requested: requested,
        background: background,
        fallback: const Color(0xFF000000),
        minimumContrast: 4.5,
      );

      expect(resolved, isNot(requested));
      expect(
        contrast.contrastRatio(resolved, background),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('preserves requested hue while adjusting tone', () {
      const requested = Color(0xFF3366CC);
      const background = Color(0xFF3366CC);
      final requestedHct = Hct.fromInt(requested.toARGB32());

      final resolved = resolver.resolveReadableForeground(
        requested: requested,
        background: background,
        fallback: const Color(0xFFFFFFFF),
        minimumContrast: 4.5,
      );
      final resolvedHct = Hct.fromInt(resolved.toARGB32());

      expect(
        _circularHueDistance(requestedHct.hue, resolvedHct.hue),
        lessThan(5),
      );
      expect(
        contrast.contrastRatio(resolved, background),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('chooses the qualifying candidate with the smaller tone change', () {
      const background = Color(0xFF757575);
      const requested = Color(0xFF838383);
      final requestedTone = Hct.fromInt(requested.toARGB32()).tone;

      final resolved = resolver.resolveReadableForeground(
        requested: requested,
        background: background,
        fallback: const Color(0xFFFFFFFF),
        minimumContrast: 4.5,
      );
      final resolvedTone = Hct.fromInt(resolved.toARGB32()).tone;

      expect(resolvedTone, greaterThan(requestedTone));
      expect(
        contrast.contrastRatio(resolved, background),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('uses semantic fallback only after generated candidates fail', () {
      const fallback = Color(0xFF010203);
      final recordingContrast = _FallbackOnlyContrast(fallback);
      final fallbackResolver = MaterialRichTextToneResolver(
        contrast: recordingContrast,
      );

      final resolved = fallbackResolver.resolveReadableForeground(
        requested: const Color(0xFF777777),
        background: const Color(0xFFFFFFFF),
        fallback: fallback,
        minimumContrast: 4.5,
      );

      expect(resolved, fallback);
      expect(recordingContrast.checkedColors.length, greaterThan(2));
    });

    test('throws a typed failure when fallback is also unreadable', () {
      expect(
        () => resolver.resolveReadableForeground(
          requested: const Color(0xFF777777),
          background: const Color(0xFF777777),
          fallback: const Color(0xFF000000),
          minimumContrast: 21,
        ),
        throwsA(
          isA<RichTextToneResolutionFailure>()
              .having(
                (failure) => failure.minimumContrast,
                'minimumContrast',
                21,
              )
              .having(
                (failure) => failure.fallbackContrast,
                'fallbackContrast',
                lessThan(21),
              ),
        ),
      );
    });

    test('validates minimum contrast and opaque surface inputs', () {
      expect(
        () => resolver.resolveReadableForeground(
          requested: const Color(0xFF000000),
          background: const Color(0xFFFFFFFF),
          fallback: const Color(0xFF000000),
          minimumContrast: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => resolver.resolveReadableForeground(
          requested: const Color(0xFF000000),
          background: const Color(0x80FFFFFF),
          fallback: const Color(0xFF000000),
          minimumContrast: 4.5,
        ),
        throwsArgumentError,
      );
    });
  });
}

double _circularHueDistance(double first, double second) {
  final direct = (first - second).abs();
  return direct > 180 ? 360 - direct : direct;
}

final class _FallbackOnlyContrast implements RichTextColorContrast {
  _FallbackOnlyContrast(this.fallback);

  final Color fallback;
  final List<Color> checkedColors = <Color>[];

  @override
  Color composite(Color foreground, Color background) {
    return Color.alphaBlend(foreground, background);
  }

  @override
  double contrastRatio(Color first, Color second) {
    checkedColors.add(first);
    return first.toARGB32() == fallback.toARGB32() ? 5 : 1;
  }
}
