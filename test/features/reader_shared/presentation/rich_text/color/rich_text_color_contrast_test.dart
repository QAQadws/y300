import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/rich_text/color/rich_text_color_contrast.dart';

void main() {
  const contrast = FlutterRichTextColorContrast();

  group('FlutterRichTextColorContrast', () {
    test('matches the WCAG black and white contrast ratio', () {
      final ratio = contrast.contrastRatio(
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
      );

      expect(ratio, closeTo(21, 0.0000001));
    });

    test('returns one for identical opaque colors', () {
      final ratio = contrast.contrastRatio(
        const Color(0xFF777777),
        const Color(0xFF777777),
      );

      expect(ratio, 1);
    });

    test('matches a known WCAG gray reference', () {
      final ratio = contrast.contrastRatio(
        const Color(0xFF777777),
        const Color(0xFFFFFFFF),
      );

      expect(ratio, closeTo(4.4780894536, 0.0000001));
    });

    test('composites translucent colors before measuring contrast', () {
      final blackOverWhite = contrast.composite(
        const Color(0x80000000),
        const Color(0xFFFFFFFF),
      );
      final whiteOverBlack = contrast.composite(
        const Color(0x80FFFFFF),
        const Color(0xFF000000),
      );

      expect(blackOverWhite.toARGB32(), 0xFF7F7F7F);
      expect(whiteOverBlack.toARGB32(), 0xFF808080);
      expect(
        contrast.contrastRatio(blackOverWhite, const Color(0xFFFFFFFF)),
        closeTo(4.0041069566, 0.0000001),
      );
      expect(
        contrast.contrastRatio(whiteOverBlack, const Color(0xFF000000)),
        closeTo(5.3172100023, 0.0000001),
      );
    });

    test('rejects contrast checks before alpha composition', () {
      expect(
        () => contrast.contrastRatio(
          const Color(0x80000000),
          const Color(0xFFFFFFFF),
        ),
        throwsArgumentError,
      );
      expect(
        () => contrast.contrastRatio(
          const Color(0xFF000000),
          const Color(0x80FFFFFF),
        ),
        throwsArgumentError,
      );
    });
  });
}
