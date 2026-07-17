import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/hct/hct.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_author_color_style.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_background_tone_resolver.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_color_adaptation_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  const resolver = MaterialForumHtmlBackgroundToneResolver();
  const policy = ForumHtmlColorAdaptationPolicy.standard;

  test('maps dark inline and block backgrounds to fixed container tones', () {
    const requested = Color(0xFFFFE082);

    final inline = resolver.resolve(
      requested: requested,
      role: ForumHtmlBackgroundRole.inlineHighlight,
      theme: _darkTheme,
      policy: policy,
    );
    final block = resolver.resolve(
      requested: requested,
      role: ForumHtmlBackgroundRole.blockSurface,
      theme: _darkTheme,
      policy: policy,
    );
    final requestedHct = Hct.fromInt(requested.toARGB32());
    final inlineHct = Hct.fromInt(inline.toARGB32());
    final blockHct = Hct.fromInt(block.toARGB32());

    expect(inlineHct.tone, closeTo(policy.darkInlineHighlightTone, 1.0));
    expect(blockHct.tone, closeTo(policy.darkBlockSurfaceTone, 1.0));
    expect(inlineHct.chroma, lessThanOrEqualTo(policy.maximumHighlightChroma));
    expect(_hueDistance(inlineHct.hue, requestedHct.hue), lessThan(8));
  });

  test('maps light highlights away from the reading surface', () {
    final mapped = resolver.resolve(
      requested: const Color(0xFF80CBC4),
      role: ForumHtmlBackgroundRole.inlineHighlight,
      theme: _lightTheme,
      policy: policy,
    );
    final mappedTone = Hct.fromInt(mapped.toARGB32()).tone;
    final surfaceTone = Hct.fromInt(_lightTheme.surface.toARGB32()).tone;

    expect(mappedTone, closeTo(policy.lightInlineHighlightTone, 1.0));
    expect(
      (mappedTone - surfaceTone).abs(),
      greaterThanOrEqualTo(policy.minimumSurfaceToneSeparation - 0.5),
    );
  });
}

double _hueDistance(double first, double second) {
  final direct = (first - second).abs();
  return direct > 180 ? 360 - direct : direct;
}

const _darkTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.dark,
  surface: Color(0xFF141414),
  foreground: Color(0xFFE9E9E9),
  link: Color(0xFF8DB7FF),
  quoteSurface: Color(0xFF242424),
  quoteForeground: Color(0xFFAAA39A),
  codeSurface: Color(0xFF202020),
  codeForeground: Color(0xFFE9E9E9),
);

const _lightTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFFDFDFD),
  foreground: Color(0xFF1F1F1F),
  link: Color(0xFF6A55A3),
  quoteSurface: Color(0xFFF1F1F1),
  quoteForeground: Color(0xFF4F4F4F),
  codeSurface: Color(0xFFF5F5F5),
  codeForeground: Color(0xFF1F1F1F),
);
