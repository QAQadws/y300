import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// A pure local copy snapshot plus its mounted source's transient validity.
/// Reading text or opening Copy never confirms navigation or reading progress.
final class NovelReaderNativeTextSelection {
  const NovelReaderNativeTextSelection(this.snapshot, this._isCurrent);
  final ForumBodyTextSelectionSnapshot snapshot;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
}
