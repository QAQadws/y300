import 'dart:math' as math;

import '../document/forum_body_document.dart';

final class ForumBodyTableLimits {
  const ForumBodyTableLimits({
    this.maxRows = 4096,
    this.maxColumns = 2048,
    this.maxCells = 8192,
    this.maxSlotChecks = 262144,
    this.maxNesting = 8,
  }) : assert(maxRows > 0),
       assert(maxColumns > 0),
       assert(maxCells > 0),
       assert(maxSlotChecks > 0),
       assert(maxNesting > 0);

  final int maxRows, maxColumns, maxCells, maxSlotChecks, maxNesting;
}

enum ForumBodyTableFailure {
  rowLimit,
  columnLimit,
  cellLimit,
  workLimit,
  overlap,
  invalidGeometry,
  extentLimit,
  nestingLimit,
}

final class ForumBodyTableException implements Exception {
  const ForumBodyTableException(this.failure, this.path);

  final ForumBodyTableFailure failure;
  final String path;

  @override
  String toString() => 'ForumBodyTableException(${failure.name}, $path)';
}

/// The row may be implied by a span. No source is invented for such a row.
typedef ForumBodyTableRow = ({
  ForumBodyElement? group,
  ForumBodyElement? element,
});

/// A range of column tracks declared by a col, or by a colgroup without cols.
typedef ForumBodyTableColumnRange = ({
  ForumBodyElement? group,
  ForumBodyElement element,
  int column,
  int span,
});

/// The cell owns one rectangular region regardless of its number of slots.
/// Children and source coordinates stay on the original cell element.
typedef ForumBodyTableCell = ({
  ForumBodyElement element,
  int row,
  int column,
  int rowSpan,
  int columnSpan,
});

/// The repaired source table's logical grid. Independent of fonts, layout
/// width, host widgets, and scroll policy. No expanded slot matrix is retained.
final class ForumBodyTableGrid {
  factory ForumBodyTableGrid.fromDocument(
    ForumBodyDocument document,
    ForumBodyElement table, {
    ForumBodyTableLimits limits = const ForumBodyTableLimits(),
  }) {
    if (table.kind != ForumBodyElementKind.table ||
        !identical(document.nodeAtPath(table.path), table)) {
      throw ArgumentError('Expected a table from the supplied document');
    }
    final nesting = document
        .ancestryOf(table)!
        .where((node) => node.kind == ForumBodyElementKind.table)
        .length;
    if (nesting > limits.maxNesting) {
      throw ForumBodyTableException(
        ForumBodyTableFailure.nestingLimit,
        table.path,
      );
    }
    return _TableGridBuilder(limits).build(document.identity, table);
  }

  ForumBodyTableGrid._(
    this.identity,
    this.table,
    this.columnCount,
    List<ForumBodyElement> captions,
    List<ForumBodyTableColumnRange> columnRanges,
    List<ForumBodyTableRow> rows,
    List<ForumBodyTableCell> cells,
  ) : captions = List.unmodifiable(captions),
      columnRanges = List.unmodifiable(columnRanges),
      rows = List.unmodifiable(rows),
      cells = List.unmodifiable(cells);

  final ForumBodyIdentity identity;
  final ForumBodyElement table;
  final int columnCount;
  final List<ForumBodyElement> captions;
  final List<ForumBodyTableColumnRange> columnRanges;
  final List<ForumBodyTableRow> rows;
  final List<ForumBodyTableCell> cells;
}

final class _TableGridBuilder {
  _TableGridBuilder(this.limits);

  final ForumBodyTableLimits limits;
  final _captions = <ForumBodyElement>[];
  final _columnRanges = <ForumBodyTableColumnRange>[];
  final _rows = <ForumBodyTableRow>[];
  final _cells = <ForumBodyTableCell>[];
  var _declaredColumns = 0, _columnCount = 0, _slotChecks = 0;

  ForumBodyTableGrid build(ForumBodyIdentity identity, ForumBodyElement table) {
    final directRows = <ForumBodyElement>[];
    final footers = <ForumBodyElement>[];
    for (final child in table.children.whereType<ForumBodyElement>()) {
      if (child.kind == ForumBodyElementKind.tableRow) {
        directRows.add(child);
        continue;
      }
      if (directRows.isNotEmpty) {
        _placeRows(directRows, null);
        directRows.clear();
      }
      switch (child.kind) {
        case ForumBodyElementKind.tableCaption:
          _captions.add(child);
        case ForumBodyElementKind.tableColumnGroup:
          final columns = child.children.whereType<ForumBodyElement>().where(
            (element) => element.kind == ForumBodyElementKind.tableColumn,
          );
          if (columns.isEmpty) _declareColumns(child, null);
          for (final column in columns) {
            _declareColumns(column, child);
          }
        case ForumBodyElementKind.tableColumn:
          _declareColumns(child, null);
        case ForumBodyElementKind.tableSection:
          if (child.tag == 'tfoot') {
            footers.add(child);
          } else {
            _placeRows(child.children.whereType<ForumBodyElement>(), child);
          }
        default:
          break;
      }
    }
    if (directRows.isNotEmpty) _placeRows(directRows, null);
    // HTML lays out footer groups after the other rows, even in older markup
    // with tfoot before tbody. The original node paths still order the source.
    for (final footer in footers) {
      _placeRows(footer.children.whereType<ForumBodyElement>(), footer);
    }
    return ForumBodyTableGrid._(
      identity,
      table,
      _columnCount,
      _captions,
      _columnRanges,
      _rows,
      _cells,
    );
  }

  void _declareColumns(ForumBodyElement element, ForumBodyElement? group) {
    final span = math.max(1, _span(element.attributes['span'], max: 1000));
    final end = _declaredColumns + span;
    if (end > limits.maxColumns) {
      _fail(ForumBodyTableFailure.columnLimit, element);
    }
    _columnRanges.add((
      group: group,
      element: element,
      column: _declaredColumns,
      span: span,
    ));
    _declaredColumns = end;
    _columnCount = math.max(_columnCount, end);
  }

  void _placeRows(Iterable<ForumBodyElement> rows, ForumBodyElement? group) {
    // One occupied-until index per column suffices when visiting rows in order.
    final occupiedUntil = <int>[];
    final downward = <int>[];
    var groupEnd = _rows.length;
    for (final row in rows) {
      if (row.kind != ForumBodyElementKind.tableRow) continue;
      if (_rows.length == limits.maxRows) {
        _fail(ForumBodyTableFailure.rowLimit, row);
      }
      final y = _rows.length;
      _rows.add((group: group, element: row));
      groupEnd = math.max(groupEnd, y + 1);
      var x = 0;
      for (final cell in row.children.whereType<ForumBodyElement>()) {
        if (cell.kind != ForumBodyElementKind.tableCell) continue;
        if (_cells.length == limits.maxCells) {
          _fail(ForumBodyTableFailure.cellLimit, cell);
        }
        final columnSpan = math.max(
          1,
          _span(cell.attributes['colspan'], max: 1000),
        );
        final rowSpan = _span(cell.attributes['rowspan'], max: 65534);
        while (x < occupiedUntil.length && occupiedUntil[x] > y) {
          _checkSlots(1, cell);
          x++;
        }
        final end = x + columnSpan;
        if (end > limits.maxColumns) {
          _fail(ForumBodyTableFailure.columnLimit, cell);
        }
        if (y + rowSpan > limits.maxRows) {
          _fail(ForumBodyTableFailure.rowLimit, cell);
        }
        _checkSlots(columnSpan, cell);
        final until = rowSpan == 0 ? limits.maxRows : y + rowSpan;
        for (var column = x; column < end; column++) {
          if (column == occupiedUntil.length) {
            occupiedUntil.add(until);
          } else {
            if (occupiedUntil[column] > y) {
              _fail(ForumBodyTableFailure.overlap, cell);
            }
            occupiedUntil[column] = until;
          }
        }
        if (rowSpan == 0) downward.add(_cells.length);
        _cells.add((
          element: cell,
          row: y,
          column: x,
          rowSpan: rowSpan,
          columnSpan: columnSpan,
        ));
        _columnCount = math.max(_columnCount, end);
        groupEnd = math.max(groupEnd, y + rowSpan);
        x = end;
      }
    }
    while (_rows.length < groupEnd) {
      _rows.add((group: group, element: null));
    }
    for (final index in downward) {
      final cell = _cells[index];
      _cells[index] = (
        element: cell.element,
        row: cell.row,
        column: cell.column,
        rowSpan: groupEnd - cell.row,
        columnSpan: cell.columnSpan,
      );
    }
  }

  void _checkSlots(int count, ForumBodyElement element) {
    _slotChecks += count;
    if (_slotChecks > limits.maxSlotChecks) {
      _fail(ForumBodyTableFailure.workLimit, element);
    }
  }

  Never _fail(ForumBodyTableFailure failure, ForumBodyElement element) =>
      throw ForumBodyTableException(failure, element.path);
}

final _leadingDigits = RegExp(r'^[\t\n\f\r ]*\+?([0-9]+)');

int _span(String? value, {required int max}) {
  final digits = value == null ? null : _leadingDigits.firstMatch(value)?[1];
  if (digits == null) return 1;
  var span = 0;
  for (var i = 0; i < digits.length; i++) {
    span = span * 10 + digits.codeUnitAt(i) - 0x30;
    if (span >= max) return max;
  }
  return span;
}
