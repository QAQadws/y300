import 'dart:collection';

import '../paragraph/forum_body_paragraph_content.dart';

typedef _Range = ({int startUtf16, int endUtf16});

enum _Category { separator, space, punctuation, excluded, other }

/// A decoration target in an original complete display grapheme. These UTF-16
/// bounds neither add copy text nor prove DOM/semantic anchor coverage.
final class ForumBodyEmphasisTextUnit {
  const ForumBodyEmphasisTextUnit._({
    required this.startUtf16,
    required this.endUtf16,
    required this.governingUtf16,
    required this.runIndex,
  });
  final int startUtf16;
  final int endUtf16;
  final int governingUtf16;
  final int runIndex;
}

/// Source/style input only, without glyph metrics, native handles or callbacks.
/// The actual paragraph identity is retained for subsequent qualified binding.
final class ForumBodyEmphasisTextInput {
  ForumBodyEmphasisTextInput._(
    this.glyphInput,
    List<ForumBodyEmphasisTextUnit> units,
  ) : units = UnmodifiableListView(units);
  static const revision = 2;
  final ForumBodyEmphasisGlyphInput glyphInput;
  ForumBodyParagraphContent get content => glyphInput.original;
  final List<ForumBodyEmphasisTextUnit> units;
}

/// Reuses the core's original grapheme boundaries, including styled seams.
/// One work unit scans one scalar, crosses one style part or closes one range.
/// A pathological combining cluster therefore cannot monopolize an advance.
final class ForumBodyEmphasisTextPreparation {
  ForumBodyEmphasisTextPreparation({
    required ForumBodyParagraphContent content,
    int maxUnits = 512,
  }) : this._(content, null, maxUnits);

  /// Reuse a qualified pure source/glyph derivation. In particular, local row
  /// windows need no second traversal of the whole parent's glyph style table.
  ForumBodyEmphasisTextPreparation.fromGlyphInput({
    required ForumBodyEmphasisGlyphInput glyphInput,
    int maxUnits = 512,
  }) : this._(glyphInput.original, glyphInput, maxUnits);

  ForumBodyEmphasisTextPreparation._(
    ForumBodyParagraphContent content,
    ForumBodyEmphasisGlyphInput? glyphInput,
    this.maxUnits,
  ) : _content = content,
      _glyphInput = glyphInput {
    if (maxUnits < 0) throw ArgumentError.value(maxUnits);
    if (content.isSourceFree) {
      throw ArgumentError('Emphasis requires actual source text');
    }
    if (glyphInput == null) {
      _glyphPreparation = ForumBodyEmphasisGlyphPreparation(content: content);
    }
    _ranges = content.projection
        .graphemeRanges(startUtf16: 0, endUtf16: content.projection.text.length)
        .iterator;
  }
  final int maxUnits;
  ForumBodyParagraphContent? _content;
  ForumBodyEmphasisGlyphPreparation? _glyphPreparation;
  ForumBodyEmphasisGlyphInput? _glyphInput;
  Iterator<_Range>? _ranges;
  List<ForumBodyEmphasisTextUnit>? _units = [];
  ForumBodyEmphasisTextInput? _result;
  _Range? _range;
  int _offset = 0, _part = 0;
  int? _governing;
  _Category? _category;
  bool _combining = false, _enclosing = false, _commonBase = false;
  bool _closed = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_closed) throw StateError('Emphasis text preparation is retired');
    var used = 0;
    try {
      while (used < maxParts && !isReady) {
        if (_glyphInput == null) {
          final preparation = _glyphPreparation!;
          used += preparation.advance(maxParts: maxParts - used);
          if (preparation.isReady) {
            _glyphInput = preparation.takeInput();
            _glyphPreparation = null;
          }
          continue;
        }
        final content = _content!;
        final range = _range;
        if (range == null) {
          if (_ranges!.moveNext()) {
            _range = _ranges!.current;
            _offset = _range!.startUtf16;
            _governing = null;
            _category = null;
            _combining = _enclosing = _commonBase = false;
          } else {
            // Transfer the retired write list; finalization never rescans or
            // copies the accumulated targets in one nominal work unit.
            _result = ForumBodyEmphasisTextInput._(_glyphInput!, _units!);
            _glyphInput = null;
            _units = null;
            _ranges = null;
            _content = null;
          }
        } else if (_offset < range.endUtf16) {
          final text = content.projection.text;
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
          // A format prepend may share a grapheme with an actual base. It is
          // neither a second target nor the owner of that base's author style.
          if (_governing == null && !_format.hasMatch(scalar)) {
            _governing = _offset;
            _category = _categoryOf(scalar);
            _commonBase = _common.hasMatch(scalar);
          }
          _offset = end;
        } else if (!_eligible) {
          _range = null;
        } else {
          final parts = content.projection.parts;
          final part = parts[_part];
          if (part.utf16Start + part.text.length <= _governing!) {
            _part++;
          } else {
            final style = content.runs[part.runIndex].style;
            if (style.textEmphasis.isEnabled) {
              if (_units!.length >= maxUnits) {
                throw ForumBodyParagraphInputException(
                  ForumBodyParagraphInputFailure.inputLimit,
                  content.path,
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

  // CSS Text's character properties use the base, with Common enclosing marks
  // treated as symbols and space+combining sequences as modifier symbols.
  // https://www.w3.org/TR/css-text-3/#character-properties
  bool get _eligible =>
      _governing != null &&
      (_enclosing && _commonBase ||
          _category == _Category.other ||
          _category == _Category.space && _combining);

  ForumBodyEmphasisTextInput takeInput() {
    if (_closed) throw StateError('Emphasis text preparation is retired');
    if (!isReady) throw StateError('Emphasis text preparation is incomplete');
    final result = _result!;
    close();
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _glyphPreparation?.close();
    _glyphPreparation = null;
    _glyphInput = null;
    _content = null;
    _ranges = null;
    _range = null;
    _units = null;
    _result = null;
  }
}

final _format = RegExp(r'^\p{Cf}$', unicode: true);
final _mark = RegExp(r'^\p{M}$', unicode: true);
final _enclosingMark = RegExp(r'^\p{Me}$', unicode: true);
final _common = RegExp(r'^\p{Script=Common}$', unicode: true);
// Inherited enclosing marks adopt the Common base's script; checking only the
// mark's literal Script would wrongly reject keycap/enclosing symbol clusters.
final _genericScript = RegExp(
  r'^[\p{Script=Common}\p{Script=Inherited}]$',
  unicode: true,
);
final _space = RegExp(r'^\p{Zs}$', unicode: true);
final _separator = RegExp(r'^\p{Z}$', unicode: true);
final _punctuation = RegExp(r'^\p{P}$', unicode: true);
final _excluded = RegExp(r'^[\p{Cc}\p{Cn}\p{Cs}]$', unicode: true);

_Category _categoryOf(String scalar) {
  if (_space.hasMatch(scalar)) return _Category.space;
  if (_separator.hasMatch(scalar)) return _Category.separator;
  if (_excluded.hasMatch(scalar)) return _Category.excluded;
  if (_punctuation.hasMatch(scalar) &&
      !_punctuationExceptions.contains(scalar)) {
    return _Category.punctuation;
  }
  return _Category.other;
}

// CSS Text Decoration 3 named punctuation plus all single-character NFKD
// equivalents in UnicodeData17.0.0. No runtime normalization dependency/scan.
// https://www.w3.org/TR/css-text-decor-3/#text-emphasis-style-property
// https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt
const _punctuationExceptions = {
  '#',
  '%',
  '&',
  '@',
  '§',
  '¶',
  '؉',
  '؊',
  '٪',
  '‰',
  '‱',
  '⁊',
  '⁋',
  '⁓',
  '〽',
  '﹟',
  '﹠',
  '﹪',
  '﹫',
  '＃',
  '％',
  '＆',
  '＠',
};
