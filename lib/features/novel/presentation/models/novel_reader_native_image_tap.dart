import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// Immutable viewer data plus transient validity of its actual mounted source.
/// An image tap grants no novel navigation or progress authority.
final class NovelReaderNativeImageTap {
  const NovelReaderNativeImageTap(this.entry, this.sequence, this._isCurrent);
  final ForumHtmlReadableImageEntry entry;
  final ForumHtmlReadableImageSequence sequence;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
}
