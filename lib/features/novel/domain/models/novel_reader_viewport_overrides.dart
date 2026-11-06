enum NovelReaderViewportEdge { left, top, right, bottom }

enum NovelReaderContentWidthMode { limited, available }

enum NovelReaderColumnCount {
  single(1),
  double(2),
  triple(3);

  const NovelReaderColumnCount(this.count);
  final int count;
}

/// A remembered finite limit remains available when full width is selected.
final class NovelReaderContentWidth {
  const NovelReaderContentWidth.limited(this.logicalPixels)
    : mode = NovelReaderContentWidthMode.limited;
  const NovelReaderContentWidth.available({this.logicalPixels = initial})
    : mode = NovelReaderContentWidthMode.available;
  static const minimum = 160.0;
  static const maximum = 2560.0;
  static const step = 10.0;
  static const initial = 720.0;
  final double logicalPixels;
  final NovelReaderContentWidthMode mode;
  bool get isValid =>
      logicalPixels.isFinite &&
      logicalPixels >= minimum &&
      logicalPixels <= maximum;
  @override
  bool operator ==(Object other) =>
      other is NovelReaderContentWidth &&
      other.logicalPixels == logicalPixels &&
      other.mode == mode;
  @override
  int get hashCode => Object.hash(logicalPixels, mode);
}

/// Physical margins in logical pixels. Null inherits; zero is an explicit edge.
/// These values belong to the viewport, never the author's HTML box model.
final class NovelReaderViewportOverrides {
  const NovelReaderViewportOverrides({
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.contentWidth,
    this.columns,
  });
  static const minimumMargin = 0.0;
  static const maximumMargin = 96.0;
  static const marginStep = 1.0;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final NovelReaderContentWidth? contentWidth;
  final NovelReaderColumnCount? columns;
  static bool validMargin(double value) =>
      value.isFinite && value >= minimumMargin && value <= maximumMargin;
  bool get isValid =>
      [left, top, right, bottom].every((v) => v == null || validMargin(v)) &&
      (contentWidth?.isValid ?? true);
  bool get isEmpty =>
      left == null &&
      top == null &&
      right == null &&
      bottom == null &&
      contentWidth == null &&
      columns == null;
  double? marginFor(NovelReaderViewportEdge edge) => switch (edge) {
    NovelReaderViewportEdge.left => left,
    NovelReaderViewportEdge.top => top,
    NovelReaderViewportEdge.right => right,
    NovelReaderViewportEdge.bottom => bottom,
  };
  NovelReaderViewportOverrides withMargin(
    NovelReaderViewportEdge edge,
    double? value,
  ) => NovelReaderViewportOverrides(
    left: edge == NovelReaderViewportEdge.left ? value : left,
    top: edge == NovelReaderViewportEdge.top ? value : top,
    right: edge == NovelReaderViewportEdge.right ? value : right,
    bottom: edge == NovelReaderViewportEdge.bottom ? value : bottom,
    contentWidth: contentWidth,
    columns: columns,
  );
  NovelReaderViewportOverrides withContentWidth(
    NovelReaderContentWidth? value,
  ) => NovelReaderViewportOverrides(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    contentWidth: value,
    columns: columns,
  );
  NovelReaderViewportOverrides withColumns(NovelReaderColumnCount value) =>
      NovelReaderViewportOverrides(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        contentWidth: contentWidth,
        columns: value,
      );
  NovelReaderViewportOverrides over(NovelReaderViewportOverrides base) =>
      NovelReaderViewportOverrides(
        left: left ?? base.left,
        top: top ?? base.top,
        right: right ?? base.right,
        bottom: bottom ?? base.bottom,
        contentWidth: contentWidth ?? base.contentWidth,
        columns: columns ?? base.columns,
      );
  @override
  bool operator ==(Object other) =>
      other is NovelReaderViewportOverrides &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.contentWidth == contentWidth &&
      other.columns == columns;
  @override
  int get hashCode =>
      Object.hash(left, top, right, bottom, contentWidth, columns);
}
