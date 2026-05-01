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

/// Persisted reader preferences.
///
/// This model is intentionally small and stable so later phases can evolve
/// implementation details without changing callers.
class ReaderPreferences {
  const ReaderPreferences({
    required this.readerMode,
    required this.showPageIndicator,
    required this.fullscreenOnOpen,
    this.cacheDirectoryPath,
  });

  /// Default value used when no persisted data exists.
  factory ReaderPreferences.defaults() {
    return const ReaderPreferences(
      readerMode: ReaderModePreference.vertical,
      showPageIndicator: true,
      fullscreenOnOpen: false,
      cacheDirectoryPath: null,
    );
  }

  final ReaderModePreference readerMode;
  final bool showPageIndicator;
  final bool fullscreenOnOpen;
  final String? cacheDirectoryPath;

  ReaderPreferences copyWith({
    ReaderModePreference? readerMode,
    bool? showPageIndicator,
    bool? fullscreenOnOpen,
    String? cacheDirectoryPath,
    bool clearCacheDirectoryPath = false,
  }) {
    return ReaderPreferences(
      readerMode: readerMode ?? this.readerMode,
      showPageIndicator: showPageIndicator ?? this.showPageIndicator,
      fullscreenOnOpen: fullscreenOnOpen ?? this.fullscreenOnOpen,
      cacheDirectoryPath: clearCacheDirectoryPath
          ? null
          : (cacheDirectoryPath ?? this.cacheDirectoryPath),
    );
  }
}

