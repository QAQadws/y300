import 'dart:collection';

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

/// Bounded numeric alignment over actual parent rows. Each base/rank merge,
/// rank check and final rank position consumes its own work allowance. No native
/// owner, layout, callback or paint/coverage proof is retained here.
final class ForumBodyRubyRowAlignment {
  ForumBodyRubyRowAlignment({
    required List<ForumBodyRubyGroupMetrics> columns,
    required List<int> levelIds,
    required List<int> atomOffsets,
  }) : this.atoms(
         atoms: [
           for (final column in columns) ForumBodyRubyColumnMetrics(column),
         ],
         levelIds: levelIds,
         atomOffsets: atomOffsets,
       );

  ForumBodyRubyRowAlignment.atoms({
    required List<ForumBodyRubyAtomMetrics> atoms,
    required List<int> levelIds,
    required List<int> atomOffsets,
  }) : atoms = List.unmodifiable(atoms),
       levelIds = List.unmodifiable(levelIds),
       atomOffsets = List.unmodifiable(atomOffsets),
       _targets = List.filled(atoms.length, null),
       _atomRows = List.filled(atoms.length, -1) {
    if (levelIds.length != atoms.length || atomOffsets.length != atoms.length) {
      throw ArgumentError('Ruby alignment input lengths differ');
    }
    if (atoms.isEmpty) _phase = _Phase.done;
  }
  final List<ForumBodyRubyAtomMetrics> atoms;
  late final List<ForumBodyRubyGroupMetrics> columns = List.unmodifiable([
    for (final atom in atoms)
      switch (atom) {
        ForumBodyRubyColumnMetrics(:final value) => value,
        _ => throw StateError('Ruby row contains a segment, not only columns'),
      },
  ]);
  final List<int> levelIds;
  final List<int> atomOffsets;
  final _dimensions = <PlaceholderDimensions>[];
  final _results = <ForumBodyRubyAtomMetrics>[];
  late final List<ForumBodyRubyAtomMetrics> _resultView = UnmodifiableListView(
    _results,
  );
  List<ForumBodyRubyAtomMetrics> get results {
    if (!isComplete) throw StateError('Ruby row alignment is incomplete');
    return _resultView;
  }

  final List<ForumBodyRubyLevelMetrics?> _targets;
  final List<int> _atomRows;
  final _globalLevels = <(int, String), ForumBodyRubyLevelUnion>{};
  final _rowLevels = <(int, int, String), ForumBodyRubyLevelUnion>{};
  final _changedRows = <(int, int, String)>{};
  ForumBodyRubyLevelMerge? _merge;
  ForumBodyRubyAtomAlignment? _columnWork;
  List<ForumBodyParagraphLine>? _rows;
  var _phase = _Phase.globalUnion;
  var _cursor = 0;
  var _row = 0;
  var _rowCount = 0;
  var _verified = 0;
  bool get isComplete => _phase == _Phase.done;
  bool get needsRows => _phase == _Phase.needsRows;
  bool get hasChanges => _changedRows.isNotEmpty;
  bool get isVerified => _verified == atoms.length;
  List<PlaceholderDimensions> get dimensions => _dimensions;
  List<ForumBodyRubyLevelMetrics?> get targets => _targets;

  void attachRows(List<ForumBodyParagraphLine> rows) {
    if (!needsRows) throw StateError('Ruby alignment does not need rows');
    if (rows.isEmpty) _invalid();
    _globalLevels.clear();
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
          final column = atoms[_cursor];
          final id = (levelIds[_cursor], column.alignmentSignature);
          final union = _globalLevels.putIfAbsent(
            id,
            ForumBodyRubyLevelUnion.new,
          );
          final merge = _merge ??= union.mergeAtom(column);
          parts += merge.advance(maxParts: maxParts - parts);
          if (merge.isComplete) {
            _merge = null;
            _dimensions.add(column.placeholderDimensions);
            _results.add(column);
            if (++_cursor == atoms.length) {
              _cursor = 0;
              _phase = _Phase.globalCheck;
            }
          }
        case _Phase.globalCheck:
          final column = atoms[_cursor];
          final level =
              _globalLevels[(levelIds[_cursor], column.alignmentSignature)]!
                  .value;
          final work = _columnWork ??= ForumBodyRubyAtomAlignment(
            atom: column,
            level: level,
          );
          parts += work.advance(maxParts: maxParts - parts);
          if (work.isComplete) {
            _columnWork = null;
            if (work.hasChanges) {
              _phase = _Phase.needsRows;
            } else if (++_cursor == atoms.length) {
              _phase = _Phase.done;
            }
          }
        case _Phase.rowUnion:
          if (_row >= _rows!.length) _invalid();
          final line = _rows![_row];
          final offset = atomOffsets[_cursor];
          if (offset >= line.engineCoverageEndUtf16) {
            _row++;
            parts++;
          } else {
            if (offset < line.engineCoverageStartUtf16) _invalid();
            final column = atoms[_cursor];
            final key = (_row, levelIds[_cursor], column.alignmentSignature);
            final union = _rowLevels.putIfAbsent(
              key,
              ForumBodyRubyLevelUnion.new,
            );
            _atomRows[_cursor] = _row;
            final merge = _merge ??= union.mergeAtom(column);
            parts += merge.advance(maxParts: maxParts - parts);
            if (merge.isComplete) {
              _merge = null;
              if (++_cursor == atoms.length) {
                _cursor = 0;
                _rows = null;
                _phase = _Phase.rowCheck;
              }
            }
          }
        case _Phase.rowCheck:
          final column = atoms[_cursor];
          final key = (
            _atomRows[_cursor],
            levelIds[_cursor],
            column.alignmentSignature,
          );
          final level = _rowLevels[key]!.value;
          final work = _columnWork ??= ForumBodyRubyAtomAlignment(
            atom: column,
            level: level,
          );
          parts += work.advance(maxParts: maxParts - parts);
          if (work.isComplete) {
            _columnWork = null;
            if (work.hasChanges) _changedRows.add(key);
            if (++_cursor == atoms.length) {
              _cursor = 0;
              _phase = _Phase.rowApply;
            }
          }
        case _Phase.rowApply:
          final column = atoms[_cursor];
          final key = (
            _atomRows[_cursor],
            levelIds[_cursor],
            column.alignmentSignature,
          );
          if (!_changedRows.contains(key)) {
            parts++;
            _cursor++;
          } else {
            final target = _rowLevels[key]!.value;
            final work = _columnWork ??= ForumBodyRubyAtomAlignment(
              atom: column,
              level: target,
              prepareResult: true,
            );
            parts += work.advance(maxParts: maxParts - parts);
            if (work.isComplete) {
              _columnWork = null;
              _targets[_cursor] = target;
              final result = work.result;
              _results[_cursor] = result;
              _dimensions[_cursor] = result.placeholderDimensions;
              _cursor++;
            }
          }
          if (_cursor == atoms.length) _phase = _Phase.done;
        case _Phase.needsRows:
        case _Phase.done:
          throw StateError('Ruby alignment has no work in this phase');
      }
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
    while (_verified < atoms.length && parts < maxParts) {
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
