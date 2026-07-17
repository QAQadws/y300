import 'dart:ui';

import 'package:material_color_utilities/hct/hct.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_author_color_style.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_color_adaptation_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

abstract interface class ForumHtmlBackgroundToneResolver {
  Color resolve({
    required Color requested,
    required ForumHtmlBackgroundRole role,
    required ForumHtmlThemeContext theme,
    required ForumHtmlColorAdaptationPolicy policy,
  });
}

final class MaterialForumHtmlBackgroundToneResolver
    implements ForumHtmlBackgroundToneResolver {
  const MaterialForumHtmlBackgroundToneResolver();

  @override
  Color resolve({
    required Color requested,
    required ForumHtmlBackgroundRole role,
    required ForumHtmlThemeContext theme,
    required ForumHtmlColorAdaptationPolicy policy,
  }) {
    final requestedHct = Hct.fromInt(requested.toARGB32());
    final surfaceTone = Hct.fromInt(theme.surface.toARGB32()).tone;
    var targetTone = switch ((theme.brightness, role)) {
      (ForumHtmlBrightness.dark, ForumHtmlBackgroundRole.inlineHighlight) =>
        policy.darkInlineHighlightTone,
      (ForumHtmlBrightness.dark, ForumHtmlBackgroundRole.blockSurface) =>
        policy.darkBlockSurfaceTone,
      (ForumHtmlBrightness.light, ForumHtmlBackgroundRole.inlineHighlight) =>
        policy.lightInlineHighlightTone,
      (ForumHtmlBrightness.light, ForumHtmlBackgroundRole.blockSurface) =>
        policy.lightBlockSurfaceTone,
    };
    final minimumSeparation = policy.minimumSurfaceToneSeparation;
    if ((targetTone - surfaceTone).abs() < minimumSeparation) {
      targetTone = theme.brightness == ForumHtmlBrightness.dark
          ? surfaceTone + minimumSeparation
          : surfaceTone - minimumSeparation;
    }
    targetTone = targetTone.clamp(0.0, 100.0);
    final chroma = requestedHct.chroma
        .clamp(0.0, policy.maximumHighlightChroma)
        .toDouble();
    return Color(Hct.from(requestedHct.hue, chroma, targetTone).toInt());
  }
}
