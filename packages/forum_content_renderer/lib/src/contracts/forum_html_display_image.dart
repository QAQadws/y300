import 'dart:ui' show Size;

/// A Host-owned display binding, separate from prepared-document resources.
///
/// Implementations retain immutable values. [identity] must also be immutable
/// and compare by value; it identifies the displayed source and cache work so
/// a replacement can reject late dimensions, frames and prefetch callbacks.
abstract interface class ForumHtmlDisplayImage {
  /// The source used for taps and layout shifts. A rewritten transport URL
  /// belongs in [identity], so it can change without changing this description.
  String get sourceUrl;
  String get cacheKey;
  Object get identity;
  bool get isSticker;
  Size? get htmlSize;
  ForumHtmlImageLayout get initialLayout;
}

/// The layout information used by HTML image widgets, without cache policies.
final class ForumHtmlImageLayout {
  const ForumHtmlImageLayout({
    this.isFallback = false,
    this.aspectRatio,
    this.displaySize,
  });

  final bool isFallback;
  final double? aspectRatio;
  final Size? displaySize;

  @override
  bool operator ==(Object other) =>
      other is ForumHtmlImageLayout &&
      other.isFallback == isFallback &&
      other.aspectRatio == aspectRatio &&
      other.displaySize == displaySize;

  @override
  int get hashCode => Object.hash(isFallback, aspectRatio, displaySize);
}

/// Cancelling prevents queued work and late UI updates. Transport work that
/// already started may still finish and populate the shared disk cache.
abstract interface class ForumHtmlImageWorkScope {
  bool get isActive;
}

final class ForumHtmlImageWorkToken implements ForumHtmlImageWorkScope {
  bool _cancelled = false;

  @override
  bool get isActive => !_cancelled;

  void cancel() {
    _cancelled = true;
  }
}
