/// Page margins of the novel reader surfaces.
///
/// Tuning guide: both values are safe knobs, but they are not interchangeable.
///
/// [verticalPagePadding] is pure visual padding on a scrolling list — changing
/// it only moves pixels.
///
/// [pagedPagePadding] is *also* an input to the pagination math. In
/// `NovelReaderHtmlPagedSurface` one `LayoutBuilder` derives the measured page
/// box (`pageWidth` / `paginationHeight`) and the rendered `Padding` from the
/// same value, and that value is part of both the pagination cache key and the
/// typography signature. So a change here re-measures and re-paginates rather
/// than stretching an existing layout. Keep it that way: never hardcode a
/// padding literal into only one of the two paths, or the page breaker will
/// measure against a box the renderer does not use and text will overflow.
///
/// Growing [pagedPagePadding] shrinks the content box, which is the direction
/// that can push a page's last line past the bottom edge if the two paths ever
/// disagree. Shrinking it is the safe direction.
abstract final class NovelReaderSpacing {
  /// Page margin of the scrolling (vertical) reading mode.
  static const double verticalPagePadding = 8;

  /// Page margin of the paged reading modes. Feeds the pagination math.
  static const double pagedPagePadding = 8;
}
