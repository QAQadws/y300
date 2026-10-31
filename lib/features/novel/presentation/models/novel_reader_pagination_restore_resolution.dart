final class NovelReaderPaginationRestoreResolution {
  const NovelReaderPaginationRestoreResolution({
    required this.pageIndex,
    required this.isReadOnlyCompatibilityRestore,
  });

  final int pageIndex;

  /// A readable page does not establish the unit of an old offset. This flag
  /// does not replace the reading session's navigation and persistence gates.
  final bool isReadOnlyCompatibilityRestore;
}
