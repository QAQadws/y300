import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_layout.dart';
import 'forum_body_ruby_group_metrics.dart';

enum _Phase {
  globalUnion,
  globalCheck,
  needsRows,
  rowUnion,
  rowCheck,
  rowApply,
  done,
}

/// Bounded numeric alignment over actual parent rows. This retains no native
/// owner, layout, callback or paint/coverage proof. The caller supplies actual
/// measured rows and guards the owner around each step.
final class ForumBodyRubyRowAlignment {
  ForumBodyRubyRowAlignment({
    required this.columns,
    required this.levelIds,
    required this.atomOffsets,
  }) : _targets = List.filled(columns.length, null),
       _atomRows = List.filled(columns.length, -1) {
    if (levelIds.length != columns.length ||
        atomOffsets.length != columns.length) {
      throw ArgumentError('Ruby alignment input lengths differ');
    }
    if (columns.isEmpty) _phase = _Phase.done;
  }

  final List<ForumBodyRubyGroupMetrics> columns;
  final List<int> levelIds;
  final List<int> atomOffsets;
  final _dimensions = <PlaceholderDimensions>[];
  final List<ForumBodyRubyLevelMetrics?> _targets;
  final List<int> _atomRows;
  final _globalLevels = <int, ForumBodyRubyLevelMetrics>{};
  final _rowLevels = <(int, int), ForumBodyRubyLevelMetrics>{};
  final _changedRows = <(int, int)>{};
  List<ForumBodyParagraphLine>? _rows;
  var _phase = _Phase.globalUnion;
  var _cursor = 0;
  var _row = 0;
  var _rowCount = 0;
  var _verified = 0;

  bool get isComplete => _phase == _Phase.done;
  bool get needsRows => _phase == _Phase.needsRows;
  bool get hasChanges => _changedRows.isNotEmpty;
  bool get isVerified => _verified == columns.length;
  List<PlaceholderDimensions> get dimensions => _dimensions;
  List<ForumBodyRubyLevelMetrics?> get targets => _targets;

  void attachRows(List<ForumBodyParagraphLine> rows) {
    if (!needsRows) throw StateError('Ruby alignment does not need rows');
    if (rows.isEmpty) _invalid();
    _rows = rows;
    _rowCount = rows.length;
    _cursor = 0;
    _phase = _Phase.rowUnion;
  }

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    var parts = 0;
    while (!isComplete && !needsRows && parts < maxParts) {
      switch (_phase) {
        case _Phase.globalUnion:
          final column = columns[_cursor];
          final id = levelIds[_cursor];
          _globalLevels[id] =
              _globalLevels[id]?.include(column) ??
              ForumBodyRubyLevelMetrics.single(column);
          _dimensions.add(column.placeholderDimensions);
          if (++_cursor == columns.length) {
            _cursor = 0;
            _phase = _Phase.globalCheck;
          }
        case _Phase.globalCheck:
          if (columns[_cursor].needsLevelAlignment(
            _globalLevels[levelIds[_cursor]]!,
          )) {
            _phase = _Phase.needsRows;
          } else if (++_cursor == columns.length) {
            _phase = _Phase.done;
          }
        case _Phase.rowUnion:
          if (_row >= _rows!.length) _invalid();
          final line = _rows![_row];
          final offset = atomOffsets[_cursor];
          if (offset >= line.engineCoverageEndUtf16) {
            _row++;
          } else {
            if (offset < line.engineCoverageStartUtf16) _invalid();
            final key = (_row, levelIds[_cursor]);
            final column = columns[_cursor];
            _atomRows[_cursor] = _row;
            _rowLevels[key] =
                _rowLevels[key]?.include(column) ??
                ForumBodyRubyLevelMetrics.single(column);
            if (++_cursor == columns.length) {
              _cursor = 0;
              _rows = null;
              _phase = _Phase.rowCheck;
            }
          }
        case _Phase.rowCheck:
          final key = (_atomRows[_cursor], levelIds[_cursor]);
          if (columns[_cursor].needsLevelAlignment(_rowLevels[key]!)) {
            _changedRows.add(key);
          }
          if (++_cursor == columns.length) {
            _cursor = 0;
            _phase = _Phase.rowApply;
          }
        case _Phase.rowApply:
          final key = (_atomRows[_cursor], levelIds[_cursor]);
          if (_changedRows.contains(key)) {
            final target = _rowLevels[key]!;
            _targets[_cursor] = target;
            _dimensions[_cursor] = columns[_cursor]
                .alignedTo(target)
                .placeholderDimensions;
          }
          if (++_cursor == columns.length) _phase = _Phase.done;
        case _Phase.needsRows:
        case _Phase.done:
          throw StateError('Ruby alignment has no work in this phase');
      }
      parts++;
    }
    return parts;
  }

  /// Vertical adjustments must not change a column's actual physical row.
  /// Validate before publishing any parent or page, also on a cached parent.
  int verifyRows(List<ForumBodyParagraphLine> rows, {required int maxParts}) {
    if (!isComplete || !hasChanges) {
      throw StateError('Ruby alignment is not final');
    }
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (rows.length != _rowCount) _invalid();
    var parts = 0;
    while (_verified < columns.length && parts < maxParts) {
      final line = rows[_atomRows[_verified]];
      final offset = atomOffsets[_verified];
      if (offset < line.engineCoverageStartUtf16 ||
          offset >= line.engineCoverageEndUtf16) {
        _invalid();
      }
      _verified++;
      parts++;
    }
    return parts;
  }

  Never _invalid() => throw const ForumBodyParagraphLayoutException(
    ForumBodyParagraphLayoutFailure.coverage,
  );
}
