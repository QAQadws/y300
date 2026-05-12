/// Reader mode options for phase-0 migration.
///
/// Notes:
/// - `vertical` keeps current behavior (long strip scrolling).
/// - `ltr`/`rtl` are reserved for upcoming paged mode in later phases.
enum ReaderModePreference {
  vertical,
  ltr,
  rtl,
}

enum ReaderPageFitPreference {
  fitWidth,
  fitHeight,
  contain,
  original,
}

enum ReaderBackgroundPreference {
  followTheme,
  black,
  white,
  gray,
}

/// Persisted reader preferences.
///
/// This model is intentionally small and stable so later phases can evolve
/// implementation details without changing callers.
class ReaderPreferences {
  const ReaderPreferences({
    required this.readerMode,
    required this.pageFit,
    required this.background,
    required this.pageSpacing,
    required this.showPageIndicator,
  });

  /// Default value used when no persisted data exists.
  factory ReaderPreferences.defaults() {
    return const ReaderPreferences(
      readerMode: ReaderModePreference.vertical,
      pageFit: ReaderPageFitPreference.fitWidth,
      background: ReaderBackgroundPreference.followTheme,
      pageSpacing: 8,
      showPageIndicator: true,
    );
  }

  final ReaderModePreference readerMode;
  final ReaderPageFitPreference pageFit;
  final ReaderBackgroundPreference background;

  /// Visual gap between pages.  The value is clamped by the controller layer
  /// before persisting so render code can use it directly.
  final double pageSpacing;
  final bool showPageIndicator;

  ReaderPreferences copyWith({
    ReaderModePreference? readerMode,
    ReaderPageFitPreference? pageFit,
    ReaderBackgroundPreference? background,
    double? pageSpacing,
    bool? showPageIndicator,
  }) {
    return ReaderPreferences(
      readerMode: readerMode ?? this.readerMode,
      pageFit: pageFit ?? this.pageFit,
      background: background ?? this.background,
      pageSpacing: pageSpacing ?? this.pageSpacing,
      showPageIndicator: showPageIndicator ?? this.showPageIndicator,
    );
  }
}
