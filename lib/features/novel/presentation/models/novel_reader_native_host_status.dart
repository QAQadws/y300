import '../controllers/novel_reader_native_paged_controller.dart';

enum NovelReaderNativeHostPhase {
  preparing,
  inactive,
  reading,
  paused,
  empty,
  failed,
  closed,
}

/// Display/control facts only. EOF/page-count changes are not reading positions.
/// The localized reader shell owns loading/recovery chrome outside contentBox.
final class NovelReaderNativeHostStatus {
  const NovelReaderNativeHostStatus({
    required this.phase,
    required this.hasVisiblePage,
    required this.isRetainingPreviousLayout,
    required this.pageCount,
    required this.isPageCountFinal,
    this.visiblePageIndex,
    this.controller,
    this.error,
  });
  final NovelReaderNativeHostPhase phase;
  final bool hasVisiblePage;
  final bool isRetainingPreviousLayout;
  final int pageCount;
  final bool isPageCountFinal;
  final int? visiblePageIndex;

  /// Borrowed command/metrics port. The Host owns and retires this controller.
  final NovelReaderNativePagedController? controller;
  final Object? error;
}
