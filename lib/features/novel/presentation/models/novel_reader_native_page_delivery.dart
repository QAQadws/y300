import 'novel_reader_native_page_view.dart';

import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

/// A requested view proposal, not evidence that a frame was actually visible.
/// UI takes view leases once, then confirms this exact request after mounting.
final class NovelReaderNativePageDelivery {
  const NovelReaderNativePageDelivery({
    required this.requestId,
    required this.view,
    required this.isReadOnlyCompatibilityRestore,
    required this.hasUserNavigated,
    this.restoredAnchor,
  });
  final int requestId;
  final NovelReaderNativePageView view;
  final bool isReadOnlyCompatibilityRestore;
  final bool hasUserNavigated;
  final NovelReaderTextAnchor? restoredAnchor;
  int get pageIndex => view.pageIndex;
}
