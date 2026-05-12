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
    required this.cropBorders,
    required this.fullscreenOnOpen,
    this.cacheDirectoryPath,
  });

  /// Default value used when no persisted data exists.
  factory ReaderPreferences.defaults() {
    return const ReaderPreferences(
      readerMode: ReaderModePreference.vertical,
      pageFit: ReaderPageFitPreference.fitWidth,
      background: ReaderBackgroundPreference.followTheme,
      pageSpacing: 8,
      showPageIndicator: true,
      cropBorders: false,
      fullscreenOnOpen: false,
      cacheDirectoryPath: null,
    );
  }

  final ReaderModePreference readerMode;
  final ReaderPageFitPreference pageFit;
  final ReaderBackgroundPreference background;

  /// Visual gap between pages.  The value is clamped by the controller layer
  /// before persisting so render code can use it directly.
  final double pageSpacing;
  final bool showPageIndicator;
  final bool cropBorders;
  final bool fullscreenOnOpen;
  final String? cacheDirectoryPath;

  ReaderPreferences copyWith({
    ReaderModePreference? readerMode,
    ReaderPageFitPreference? pageFit,
    ReaderBackgroundPreference? background,
    double? pageSpacing,
    bool? showPageIndicator,
    bool? cropBorders,
    bool? fullscreenOnOpen,
    String? cacheDirectoryPath,
    bool clearCacheDirectoryPath = false,
  }) {
    return ReaderPreferences(
      readerMode: readerMode ?? this.readerMode,
      pageFit: pageFit ?? this.pageFit,
      background: background ?? this.background,
      pageSpacing: pageSpacing ?? this.pageSpacing,
      showPageIndicator: showPageIndicator ?? this.showPageIndicator,
      cropBorders: cropBorders ?? this.cropBorders,
      fullscreenOnOpen: fullscreenOnOpen ?? this.fullscreenOnOpen,
      cacheDirectoryPath: clearCacheDirectoryPath
          ? null
          : (cacheDirectoryPath ?? this.cacheDirectoryPath),
    );
  }
}
