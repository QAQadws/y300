import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';

/// Maps Quill's logical document offsets to raw BBCode offsets.
///
/// BBCode formatting tags have no logical Quill width. Attachment and sticker
/// tokens have width one in Quill and map to their complete raw token span.
class ComposerQuillSelectionAdapter {
  const ComposerQuillSelectionAdapter();

  ComposerSelection? toSourceSelection({
    required String source,
    required Document document,
    required TextSelection selection,
  }) {
    final index = _SourceIndex(source: source, document: document);
    final start = index.rawOffsetForLogical(selection.start);
    final end = index.rawOffsetForLogical(selection.end);
    if (start == null || end == null) {
      return null;
    }
    return ComposerSelection(start: start, end: end);
  }

  TextSelection? toQuillSelection({
    required String source,
    required Document document,
    required ComposerSelection selection,
  }) {
    final index = _SourceIndex(source: source, document: document);
    final start = index.logicalOffsetForRaw(selection.start);
    final end = index.logicalOffsetForRaw(selection.end);
    if (start == null || end == null) {
      return null;
    }
    final maxOffset = (document.length - 1).clamp(0, document.length).toInt();
    return TextSelection(
      baseOffset: start.clamp(0, maxOffset).toInt(),
      extentOffset: end.clamp(0, maxOffset).toInt(),
    );
  }
}

class _SourceIndex {
  _SourceIndex({required this.source, required this.document}) {
    _build();
  }

  final String source;
  final Document document;
  final List<_LogicalUnit> _units = <_LogicalUnit>[];

  int get _logicalLength => _units.length;

  void _build() {
    final tokenPattern = RegExp(
      r'\[attach\][^\[]+\[/attach\]'
      r'|\{:[^}]+:\}'
      r'|\[/?(?:b|i|u|s|quote)\]'
      r'|\[/?(?:color|backcolor|size|url|align)(?:=[^\]]+)?\]',
      caseSensitive: false,
    );
    var rawOffset = 0;
    for (final match in tokenPattern.allMatches(source)) {
      _appendText(source.substring(rawOffset, match.start), rawOffset);
      final token = match.group(0)!;
      if (RegExp(r'^\[attach\]', caseSensitive: false).hasMatch(token) ||
          token.startsWith('{:')) {
        _units.add(
          _LogicalUnit(
            logicalStart: _logicalLength,
            rawStart: match.start,
            rawEnd: match.end,
          ),
        );
      }
      rawOffset = match.end;
    }
    _appendText(source.substring(rawOffset), rawOffset);

    // Codec documents always contain a terminal newline. It is synthetic
    // when the raw source does not end with one and has no raw span.
    if (_units.isEmpty || source.endsWith('\n') == false) {
      _units.add(
        _LogicalUnit(
          logicalStart: _logicalLength,
          rawStart: source.length,
          rawEnd: source.length,
        ),
      );
    }
  }

  void _appendText(String text, int rawStart) {
    for (var index = 0; index < text.length; index += 1) {
      _units.add(
        _LogicalUnit(
          logicalStart: _logicalLength,
          rawStart: rawStart + index,
          rawEnd: rawStart + index + 1,
        ),
      );
    }
  }

  int? rawOffsetForLogical(int offset) {
    final normalized = offset.clamp(0, document.length).toInt();
    if (normalized == 0) {
      return 0;
    }
    for (final unit in _units) {
      if (normalized == unit.logicalStart) {
        return unit.rawStart;
      }
      if (normalized == unit.logicalEnd) {
        return unit.rawEnd;
      }
    }
    return normalized == _logicalLength ? source.length : null;
  }

  int? logicalOffsetForRaw(int offset) {
    final normalized = offset.clamp(0, source.length).toInt();
    if (normalized == 0) {
      return 0;
    }
    for (final unit in _units) {
      if (normalized == unit.rawStart) {
        return unit.logicalStart;
      }
      if (normalized == unit.rawEnd) {
        return unit.logicalEnd;
      }
    }
    return normalized == source.length ? _logicalLength : null;
  }
}

class _LogicalUnit {
  const _LogicalUnit({
    required this.logicalStart,
    required this.rawStart,
    required this.rawEnd,
  });

  final int logicalStart;
  final int rawStart;
  final int rawEnd;

  int get logicalEnd => logicalStart + 1;
}
