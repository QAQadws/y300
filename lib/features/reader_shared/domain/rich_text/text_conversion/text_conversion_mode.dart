/// Text conversion direction used by both thread and novel readers.
///
/// Mirrors [ThreadPostTextConversionMode] which is kept in place for
/// backward compat; new code should use this shared enum.
enum TextConversionMode {
  /// No conversion — text is displayed as-is.
  none,

  /// Convert traditional → simplified Chinese.
  toSimplified,

  /// Convert simplified → traditional Chinese.
  toTraditional,
}
