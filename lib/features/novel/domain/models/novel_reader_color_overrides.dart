/// Opaque sRGB reader requests. Null inherits the selected preset; RGB black
/// (zero) is a real request. Author text colors remain independent.
final class NovelReaderColorOverrides {
  const NovelReaderColorOverrides({this.foreground, this.background});
  final int? foreground;
  final int? background;
  static bool validRgb(int value) => value >= 0 && value <= 0xffffff;
  bool get isValid =>
      (foreground == null || validRgb(foreground!)) &&
      (background == null || validRgb(background!));
  bool get isEmpty => foreground == null && background == null;
  NovelReaderColorOverrides withForeground(int? value) =>
      NovelReaderColorOverrides(foreground: value, background: background);
  NovelReaderColorOverrides withBackground(int? value) =>
      NovelReaderColorOverrides(foreground: foreground, background: value);
  NovelReaderColorOverrides over(NovelReaderColorOverrides base) =>
      NovelReaderColorOverrides(
        foreground: foreground ?? base.foreground,
        background: background ?? base.background,
      );
  @override
  bool operator ==(Object other) =>
      other is NovelReaderColorOverrides &&
      other.foreground == foreground &&
      other.background == background;
  @override
  int get hashCode => Object.hash(foreground, background);
}
