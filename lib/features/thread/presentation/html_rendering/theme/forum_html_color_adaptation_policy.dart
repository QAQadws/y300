import 'package:flutter/foundation.dart';

@immutable
final class ForumHtmlColorAdaptationPolicy {
  const ForumHtmlColorAdaptationPolicy({
    this.minimumTextContrast = 4.5,
    this.maximumHighlightChroma = 32.0,
    this.darkInlineHighlightTone = 30.0,
    this.darkBlockSurfaceTone = 24.0,
    this.lightInlineHighlightTone = 90.0,
    this.lightBlockSurfaceTone = 94.0,
    this.minimumSurfaceToneSeparation = 6.0,
  }) : assert(
         minimumTextContrast >= 1 && minimumTextContrast <= 21,
         'minimumTextContrast must be between 1 and 21.',
       ),
       assert(
         maximumHighlightChroma >= 0 &&
             maximumHighlightChroma < double.infinity,
         'maximumHighlightChroma must be finite and non-negative.',
       ),
       assert(darkInlineHighlightTone >= 0 && darkInlineHighlightTone <= 100),
       assert(darkBlockSurfaceTone >= 0 && darkBlockSurfaceTone <= 100),
       assert(lightInlineHighlightTone >= 0 && lightInlineHighlightTone <= 100),
       assert(lightBlockSurfaceTone >= 0 && lightBlockSurfaceTone <= 100),
       assert(
         minimumSurfaceToneSeparation >= 0 &&
             minimumSurfaceToneSeparation <= 100,
       );

  static const standard = ForumHtmlColorAdaptationPolicy();

  final double minimumTextContrast;
  final double maximumHighlightChroma;
  final double darkInlineHighlightTone;
  final double darkBlockSurfaceTone;
  final double lightInlineHighlightTone;
  final double lightBlockSurfaceTone;
  final double minimumSurfaceToneSeparation;
}
