import '../inline/forum_body_inline_paragraph_view.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_layout.dart';

/// One complete prepared fragment. Each concurrently mounted view must own
/// distinct handles even when they share the same cache entry. These values
/// are transient delivery handles, never published snapshot metadata.
sealed class ForumBodyPreparedTextFragment {
  const ForumBodyPreparedTextFragment._();
  factory ForumBodyPreparedTextFragment.paragraph({
    required ForumBodyParagraphLease lease,
    required int startLine,
    required int endLine,
  }) = ForumBodyPreparedParagraphFragment;
  factory ForumBodyPreparedTextFragment.inline(
    ForumBodyInlineParagraphView view,
  ) = ForumBodyPreparedInlineFragment;
  bool get isActive;

  /// Borrowed for the same owner's page-budget checks and lifecycle counts.
  /// Reading this list never acquires aliases or transfers the handles.
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases;
  void close();
}

final class ForumBodyPreparedParagraphFragment
    extends ForumBodyPreparedTextFragment {
  ForumBodyPreparedParagraphFragment({
    required this.lease,
    required this.startLine,
    required this.endLine,
  }) : super._() {
    try {
      if (!lease.isActive || lease.layout.isDisposed) {
        throw StateError('Prepared paragraph is retired');
      }
      if (lease.layout.lines.isEmpty) {
        if (startLine != 0 || endLine != 0) {
          throw RangeError('Empty paragraph window');
        }
      } else {
        lease.layout.fragment(startLine, endLine);
      }
    } catch (_) {
      lease.release();
      rethrow;
    }
  }
  final ForumBodyParagraphLease lease;
  final int startLine;
  final int endLine;
  ForumBodyParagraphFragment? get view => lease.layout.lines.isEmpty
      ? null
      : lease.layout.fragment(startLine, endLine);
  @override
  bool get isActive => lease.isActive && !lease.layout.isDisposed;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [lease];
  @override
  void close() => lease.release();
}

final class ForumBodyPreparedInlineFragment
    extends ForumBodyPreparedTextFragment {
  const ForumBodyPreparedInlineFragment(this.view) : super._();
  final ForumBodyInlineParagraphView view;
  @override
  bool get isActive => view.isActive;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => view.nativeLeases;
  @override
  void close() => view.close();
}
