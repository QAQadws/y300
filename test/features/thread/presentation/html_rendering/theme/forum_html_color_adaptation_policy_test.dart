import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_color_adaptation_policy.dart';

void main() {
  group('ForumHtmlColorAdaptationPolicy', () {
    test('centralizes the standard readability and container tones', () {
      const policy = ForumHtmlColorAdaptationPolicy.standard;

      expect(policy.minimumTextContrast, 4.5);
      expect(policy.maximumHighlightChroma, 32);
      expect(policy.darkInlineHighlightTone, 30);
      expect(policy.darkBlockSurfaceTone, 24);
      expect(policy.lightInlineHighlightTone, 90);
      expect(policy.lightBlockSurfaceTone, 94);
      expect(policy.minimumSurfaceToneSeparation, 6);
    });

    test('rejects values outside supported contrast and tone ranges', () {
      expect(
        () => ForumHtmlColorAdaptationPolicy(minimumTextContrast: 0.9),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ForumHtmlColorAdaptationPolicy(darkInlineHighlightTone: 101),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ForumHtmlColorAdaptationPolicy(
          maximumHighlightChroma: double.infinity,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ForumHtmlColorAdaptationPolicy(minimumSurfaceToneSeparation: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
