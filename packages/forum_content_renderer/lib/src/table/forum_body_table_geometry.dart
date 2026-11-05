import 'dart:math' as math;
import 'dart:ui' show Rect, Size, TextDirection;

import 'forum_body_table_grid.dart';

/// Physical extents from the shared cell renderer, including box edges.
/// Minimum admits the actual content; preferred uses its natural width.
typedef ForumBodyTableWidth = ({double minimum, double preferred});

/// Frozen column widths. Measure each actual cell at [cellWidth] before
/// resolving rows. The geometry never requests another native measurement.
final class ForumBodyTableColumns {
  factory ForumBodyTableColumns.resolve({
    required ForumBodyTableGrid grid,
    required double availableWidth,
    required List<ForumBodyTableWidth> cellWidths,
    List<ForumBodyTableWidth> columnWidths = const [],
    ForumBodyTableWidth captionWidth = (minimum: 0, preferred: 0),
    double? specifiedWidth,
    double spacing = 0,
  }) {
    if (cellWidths.length != grid.cells.length ||
        (columnWidths.isNotEmpty && columnWidths.length != grid.columnCount)) {
      throw ArgumentError('Table width inputs do not match its source grid');
    }
    final path = grid.table.path;
    _checkExtent(availableWidth, path);
    _checkExtent(spacing, path);
    if (specifiedWidth != null) _checkExtent(specifiedWidth, path);
    _checkWidth(captionWidth, path);

    final requirements = <_TrackWidth>[];
    void add(int start, int span, ForumBodyTableWidth width, String source) {
      _checkWidth(width, source);
      final gaps = spacing * (span - 1);
      requirements.add((
        start: start,
        end: start + span,
        minimum: math.max(0, width.minimum - gaps),
        preferred: math.max(0, width.preferred - gaps),
      ));
    }

    for (final (index, width) in columnWidths.indexed) {
      add(index, 1, width, path);
    }
    for (final (index, cell) in grid.cells.indexed) {
      add(cell.column, cell.columnSpan, cellWidths[index], cell.element.path);
    }
    final count = grid.columnCount;
    final minimum = _minimumTracks(count, [
      for (final r in requirements)
        (start: r.start, end: r.end, extent: r.minimum),
    ]);
    final preferred = _preferredTracks(count, requirements);
    final gaps = spacing * math.max(0, count - 1);
    final minTotal = _sum(minimum);
    final preferredTotal = _sum(preferred);
    final target = math.max(
      math.max(minTotal + gaps, captionWidth.minimum),
      specifiedWidth ??
          math.min(
            availableWidth,
            math.max(preferredTotal + gaps, captionWidth.preferred),
          ),
    );
    _checkExtent(target, path);
    final assignable = target - gaps;
    final List<double> tracks;
    if (count == 0) {
      tracks = const [];
    } else if (assignable >= preferredTotal) {
      final extra = (assignable - preferredTotal) / count;
      tracks = [for (final width in preferred) width + extra];
    } else {
      // A convex combination of two feasible vectors keeps every cell's
      // minimum intact, including intervals that overlap in different rows.
      final fraction = ((assignable - minTotal) / (preferredTotal - minTotal))
          .clamp(0.0, 1.0);
      tracks = [
        for (var i = 0; i < count; i++)
          minimum[i] + (preferred[i] - minimum[i]) * fraction,
      ];
    }
    final axis = _TrackAxis(tracks, spacing);
    return ForumBodyTableColumns._(
      grid,
      axis,
      count == 0 ? target : axis.extent,
    );
  }

  const ForumBodyTableColumns._(this.grid, this._axis, this.width);
  final ForumBodyTableGrid grid;
  final _TrackAxis _axis;
  final double width;
  List<double> get widths => _axis.lengths;

  double cellWidth(int index) {
    final cell = grid.cells[index];
    return _axis.span(cell.column, cell.columnSpan);
  }

  /// The height input for each original cell is its measured outer height at
  /// the frozen width, including padding and borders. Row hints are minima.
  ForumBodyTableGeometry resolveRows({
    required List<double> cellHeights,
    List<double> rowMinimums = const [],
    TextDirection direction = TextDirection.ltr,
    double spacing = 0,
  }) {
    if (cellHeights.length != grid.cells.length ||
        (rowMinimums.isNotEmpty && rowMinimums.length != grid.rows.length)) {
      throw ArgumentError('Table height inputs do not match its source grid');
    }
    final path = grid.table.path;
    _checkExtent(spacing, path);
    final requirements = <_TrackMinimum>[
      for (final (index, height) in rowMinimums.indexed)
        (start: index, end: index + 1, extent: _checkExtent(height, path)),
      for (final (index, cell) in grid.cells.indexed)
        (
          start: cell.row,
          end: cell.row + cell.rowSpan,
          extent: math.max(
            0,
            _checkExtent(cellHeights[index], cell.element.path) -
                spacing * (cell.rowSpan - 1),
          ),
        ),
    ];
    final rows = _TrackAxis(
      _minimumTracks(grid.rows.length, requirements),
      spacing,
    );
    _checkExtent(rows.extent, path);
    return ForumBodyTableGeometry._(this, rows, direction);
  }
}

/// Full grid geometry for any Host viewport. Captions are separate measured
/// blocks in the same table surface, so the grid coordinates start below them.
final class ForumBodyTableGeometry {
  const ForumBodyTableGeometry._(this.columns, this._rows, this.direction);
  final ForumBodyTableColumns columns;
  final _TrackAxis _rows;
  final TextDirection direction;

  ForumBodyTableGrid get grid => columns.grid;
  List<double> get rowHeights => _rows.lengths;
  Size get size => Size(columns.width, _rows.extent);

  Rect rowBounds(int index) =>
      Rect.fromLTWH(0, _rows.starts[index], columns.width, rowHeights[index]);

  Rect cellBounds(int index) {
    final cell = grid.cells[index];
    final width = columns.cellWidth(index);
    final start = columns._axis.starts[cell.column];
    return Rect.fromLTWH(
      direction == TextDirection.ltr ? start : columns.width - start - width,
      _rows.starts[cell.row],
      width,
      _rows.span(cell.row, cell.rowSpan),
    );
  }
}

typedef _TrackMinimum = ({int start, int end, double extent});
typedef _TrackWidth = ({int start, int end, double minimum, double preferred});

// Each minimum is a lower bound on the difference between two prefix sums.
// The longest path in this forward-only graph gives the smallest total that
// satisfies them all, without scanning every slot in a long rowspan.
List<double> _minimumTracks(int count, List<_TrackMinimum> requirements) {
  final endingAt = List<List<_TrackMinimum>?>.filled(count + 1, null);
  for (final requirement in requirements) {
    (endingAt[requirement.end] ??= []).add(requirement);
  }
  final prefix = List.filled(count + 1, 0.0);
  for (var end = 1; end <= count; end++) {
    var extent = prefix[end - 1];
    final ending = endingAt[end];
    if (ending != null) {
      for (final r in ending) {
        extent = math.max(extent, prefix[r.start] + r.extent);
      }
    }
    prefix[end] = extent;
  }
  return [for (var i = 0; i < count; i++) prefix[i + 1] - prefix[i]];
}

List<double> _preferredTracks(int count, List<_TrackWidth> requirements) {
  requirements.sort((a, b) {
    final span = (a.end - a.start).compareTo(b.end - b.start);
    if (span != 0) return span;
    final start = a.start.compareTo(b.start);
    return start == 0 ? b.preferred.compareTo(a.preferred) : start;
  });
  final widths = List.filled(count, 0.0);
  for (final r in requirements) {
    var missing = r.preferred;
    for (var i = r.start; i < r.end; i++) {
      missing -= widths[i];
    }
    if (missing <= 0) continue;
    final extra = missing / (r.end - r.start);
    for (var i = r.start; i < r.end; i++) {
      widths[i] += extra;
    }
  }
  return widths;
}

final class _TrackAxis {
  _TrackAxis(List<double> lengths, this.spacing)
    : lengths = List.unmodifiable(lengths),
      starts = List<double>.filled(lengths.length + 1, 0) {
    for (var i = 0; i < lengths.length; i++) {
      starts[i + 1] = starts[i] + lengths[i] + spacing;
    }
  }

  final List<double> lengths, starts;
  final double spacing;
  double get extent => lengths.isEmpty ? 0 : starts.last - spacing;

  double span(int start, int count) =>
      starts[start + count] - starts[start] - spacing;
}

double _sum(List<double> values) =>
    values.fold(0.0, (sum, value) => sum + value);

void _checkWidth(ForumBodyTableWidth width, String path) {
  _checkExtent(width.minimum, path);
  _checkExtent(width.preferred, path);
  if (width.preferred < width.minimum) {
    throw ForumBodyTableException(ForumBodyTableFailure.invalidGeometry, path);
  }
}

double _checkExtent(double value, String path) {
  if (!value.isFinite || value < 0) {
    throw ForumBodyTableException(ForumBodyTableFailure.invalidGeometry, path);
  }
  if (value > 1048576) {
    throw ForumBodyTableException(ForumBodyTableFailure.extentLimit, path);
  }
  return value;
}
