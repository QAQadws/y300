/// Defaults and supported logical-pixel range for the shared page margin.
///
/// Both reading modes use the live preferences.pagePadding. Paged measurement,
/// visible insets and the layout cache identity must derive from that same value
/// so increasing a margin re-paginates instead of overflowing an old page.
abstract final class NovelReaderSpacing {
  static const double minimumPagePadding = 0;
  static const double maximumPagePadding = 48;

  /// Page margin of the scrolling (vertical) reading mode.
  static const double verticalPagePadding = 8;

  /// Page margin of the paged reading modes. Feeds the pagination math.
  static const double pagedPagePadding = 8;
}
