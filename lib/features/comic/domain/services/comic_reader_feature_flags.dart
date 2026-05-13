/// Runtime switches for the comic reader rollout path.
///
/// The flags are plain values instead of global state so controllers,
/// adapters and tests can override one capability without coupling rollout
/// policy to UI widgets or persistence details.
class ComicReaderFeatureFlags {
  const ComicReaderFeatureFlags({
    this.readerStrictCompleteRead = true,
    this.readerPreloadQueueEnabled = true,
    this.readerNextChapterPreloadEnabled = true,
    this.readerCustomMetadataEnabled = true,
    this.readerRefreshMultiKeywordEnabled = false,
  });

  /// Marks a chapter read only after the last page is visible and decoded.
  final bool readerStrictCompleteRead;

  /// Enables the prioritized disk preload queue around the current page.
  final bool readerPreloadQueueEnabled;

  /// Enables loading and caching the first pages of the next chapter.
  final bool readerNextChapterPreloadEnabled;

  /// Enables user metadata fields in detail display and refresh requests.
  final bool readerCustomMetadataEnabled;

  /// Enables trying lower-priority search keywords if the first keyword fails.
  final bool readerRefreshMultiKeywordEnabled;

  static const ComicReaderFeatureFlags defaults = ComicReaderFeatureFlags();

  ComicReaderFeatureFlags copyWith({
    bool? readerStrictCompleteRead,
    bool? readerPreloadQueueEnabled,
    bool? readerNextChapterPreloadEnabled,
    bool? readerCustomMetadataEnabled,
    bool? readerRefreshMultiKeywordEnabled,
  }) {
    return ComicReaderFeatureFlags(
      readerStrictCompleteRead:
          readerStrictCompleteRead ?? this.readerStrictCompleteRead,
      readerPreloadQueueEnabled:
          readerPreloadQueueEnabled ?? this.readerPreloadQueueEnabled,
      readerNextChapterPreloadEnabled:
          readerNextChapterPreloadEnabled ?? this.readerNextChapterPreloadEnabled,
      readerCustomMetadataEnabled:
          readerCustomMetadataEnabled ?? this.readerCustomMetadataEnabled,
      readerRefreshMultiKeywordEnabled:
          readerRefreshMultiKeywordEnabled ?? this.readerRefreshMultiKeywordEnabled,
    );
  }
}
