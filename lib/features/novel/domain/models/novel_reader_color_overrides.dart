import 'novel_reader_typography_overrides.dart';

/// Opaque sRGB reader requests. Null inherits the selected preset; RGB black
/// (zero) is a real request. Author text colors remain independent.
final class NovelReaderColorOverrides {
  const NovelReaderColorOverrides({
    this.foreground,
    this.background,
    this.foregroundScope,
    this.backgroundScope,
  });
  final int? foreground;
  final int? background;
  final NovelReaderStyleScope? foregroundScope;
  final NovelReaderStyleScope? backgroundScope;
  static bool validRgb(int value) => value >= 0 && value <= 0xffffff;
  bool get isValid =>
      (foreground == null || validRgb(foreground!)) &&
      (background == null || validRgb(background!));
  bool get hasCustomColors => foreground != null || background != null;
  bool get isEmpty =>
      !hasCustomColors && foregroundScope == null && backgroundScope == null;
  NovelReaderColorOverrides withForeground(int? value) =>
      NovelReaderColorOverrides(
        foreground: value,
        background: background,
        foregroundScope: foregroundScope,
        backgroundScope: backgroundScope,
      );
  NovelReaderColorOverrides withBackground(int? value) =>
      NovelReaderColorOverrides(
        foreground: foreground,
        background: value,
        foregroundScope: foregroundScope,
        backgroundScope: backgroundScope,
      );
  NovelReaderColorOverrides withForegroundScope(NovelReaderStyleScope? value) =>
      NovelReaderColorOverrides(
        foreground: foreground,
        background: background,
        foregroundScope: value,
        backgroundScope: backgroundScope,
      );
  NovelReaderColorOverrides withBackgroundScope(NovelReaderStyleScope? value) =>
      NovelReaderColorOverrides(
        foreground: foreground,
        background: background,
        foregroundScope: foregroundScope,
        backgroundScope: value,
      );
  NovelReaderColorOverrides over(NovelReaderColorOverrides base) =>
      NovelReaderColorOverrides(
        foreground: foreground ?? base.foreground,
        background: background ?? base.background,
        foregroundScope: foregroundScope ?? base.foregroundScope,
        backgroundScope: backgroundScope ?? base.backgroundScope,
      );
  @override
  bool operator ==(Object other) =>
      other is NovelReaderColorOverrides &&
      other.foreground == foreground &&
      other.background == background &&
      other.foregroundScope == foregroundScope &&
      other.backgroundScope == backgroundScope;
  @override
  int get hashCode =>
      Object.hash(foreground, background, foregroundScope, backgroundScope);
}
