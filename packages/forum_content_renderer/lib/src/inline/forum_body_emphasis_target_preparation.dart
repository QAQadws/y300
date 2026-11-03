part of 'forum_body_emphasis_text_input.dart';

/// One classifier over the original whole display projection. Inline atoms
/// delimit already legal grapheme intervals; their contents are not rescanned
/// as parent text. Style-part skips and scalar classification remain bounded.
final class _EmphasisTargetPreparation {
  _EmphasisTargetPreparation({
    required HtmlDisplayTextProjection projection,
    required List<ForumBodyParagraphRun> runs,
    required String? path,
    required this.maxUnits,
    HtmlInlineTextProjection? inline,
  }) : _projection = projection,
       _runs = runs,
       _path = path,
       _inline = inline;
  final int maxUnits;
  HtmlDisplayTextProjection? _projection;
  HtmlInlineTextProjection? _inline;
  List<ForumBodyParagraphRun>? _runs;
  String? _path;
  Iterator<_Range>? _ranges;
  List<ForumBodyEmphasisTextUnit>? _units = [], _result;
  _Range? _range;
  int _offset = 0, _part = 0, _intervalEnd = 0, _atom = 0;
  int? _governing;
  _Category? _category;
  bool _combining = false, _enclosing = false, _commonBase = false;
  bool _closed = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_closed) throw StateError('Emphasis targets are retired');
    var used = 0;
    try {
      while (used < maxParts && !isReady) {
        final projection = _projection!, range = _range;
        if (_ranges == null) {
          final atoms = _inline?.atoms;
          if (atoms != null &&
              _atom < atoms.length &&
              _intervalEnd == atoms[_atom].displayStartUtf16) {
            _intervalEnd = atoms[_atom++].displayEndUtf16;
          } else if (_intervalEnd == projection.text.length) {
            _result = _units;
            _units = null;
            _projection = null;
            _inline = null;
            _runs = null;
            _path = null;
          } else {
            final end = atoms != null && _atom < atoms.length
                ? atoms[_atom].displayStartUtf16
                : projection.text.length;
            _ranges = projection
                .graphemeRanges(startUtf16: _intervalEnd, endUtf16: end)
                .iterator;
            _intervalEnd = end;
          }
        } else if (range == null) {
          if (_ranges!.moveNext()) {
            _range = _ranges!.current;
            _offset = _range!.startUtf16;
            _governing = null;
            _category = null;
            _combining = _enclosing = _commonBase = false;
          } else {
            _ranges = null;
          }
        } else if (_offset < range.endUtf16) {
          final text = projection.text;
          final first = text.codeUnitAt(_offset);
          var end = _offset + 1;
          if (first >= 0xd800 && first <= 0xdbff && end < range.endUtf16) {
            final second = text.codeUnitAt(end);
            if (second >= 0xdc00 && second <= 0xdfff) end++;
          }
          final scalar = text.substring(_offset, end);
          _combining |= _mark.hasMatch(scalar);
          _enclosing |=
              _enclosingMark.hasMatch(scalar) &&
              _genericScript.hasMatch(scalar);
          if (_governing == null && !_format.hasMatch(scalar)) {
            _governing = _offset;
            _category = _categoryOf(scalar);
            _commonBase = _common.hasMatch(scalar);
          }
          _offset = end;
        } else if (!_eligible) {
          _range = null;
        } else {
          final part = projection.parts[_part];
          if (part.utf16Start + part.text.length <= _governing!) {
            _part++;
          } else {
            final style = _runs![part.runIndex].style;
            if (style.textEmphasis.isEnabled) {
              if (_units!.length >= maxUnits) {
                throw ForumBodyParagraphInputException(
                  ForumBodyParagraphInputFailure.inputLimit,
                  _path,
                );
              }
              _units!.add(
                ForumBodyEmphasisTextUnit._(
                  startUtf16: range.startUtf16,
                  endUtf16: range.endUtf16,
                  governingUtf16: _governing!,
                  runIndex: part.runIndex,
                ),
              );
            }
            _range = null;
          }
        }
        used++;
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    }
  }

  // Existing whole-grapheme character policy: a Common enclosing mark or
  // space+combining sequence is a symbol; a prepend does not own the style.
  bool get _eligible =>
      _governing != null &&
      (_enclosing && _commonBase ||
          _category == _Category.other ||
          _category == _Category.space && _combining);

  List<ForumBodyEmphasisTextUnit> takeUnits() {
    if (_closed) throw StateError('Emphasis targets are retired');
    if (!isReady) throw StateError('Emphasis targets are incomplete');
    final result = _result!;
    close();
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _projection = null;
    _inline = null;
    _runs = null;
    _path = null;
    _ranges = null;
    _range = null;
    _units = null;
    _result = null;
  }
}
