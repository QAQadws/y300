/// Shared limits for stored preferences and optimistic reader controls.
abstract final class ForumHtmlReaderPreferencePolicy {
  static double clampFontScale(double value) =>
      value.clamp(0.7, 2.0).toDouble();

  static double clampLineHeight(double value) =>
      value.clamp(1.0, 2.5).toDouble();
}
