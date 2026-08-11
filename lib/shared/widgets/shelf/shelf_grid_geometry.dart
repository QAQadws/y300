/// Shared geometry for grid-mode shelf covers.
///
/// Keeping these values together prevents the cover chrome and grid layout
/// from drifting apart when the shelf density is adjusted.
abstract final class ShelfGridGeometry {
  static const double contentPadding = 8;
  static const double itemSpacing = 4;

  static const double selectionCornerRadius =8;
  static const double coverCornerRadius = 7;
  static const double selectionPadding = 2;
  static const double selectionBorderWidth = 2;
}
