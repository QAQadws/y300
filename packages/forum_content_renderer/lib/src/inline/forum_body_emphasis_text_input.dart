import 'dart:collection';

import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_content.dart';

part 'forum_body_emphasis_target_preparation.dart';

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
/// One work unit processes one scalar, style part or source interval/range.
/// A pathological combining cluster therefore cannot monopolize an advance.
final class ForumBodyEmphasisTextPreparation {
  ForumBodyEmphasisTextPreparation({
    required ForumBodyParagraphContent content,
    int maxUnits = 512,
  }) : this._(content, null, maxUnits);

  /// Reuse an explicit source/glyph derivation, including legal row windows.
  ForumBodyEmphasisTextPreparation.fromGlyphInput({
    required ForumBodyEmphasisGlyphInput glyphInput,
    int maxUnits = 512,
  }) : this._(glyphInput.original, glyphInput, maxUnits);

  ForumBodyEmphasisTextPreparation._(
    ForumBodyParagraphContent content,
    ForumBodyEmphasisGlyphInput? glyphInput,
    this.maxUnits,
  ) : _glyphInput = glyphInput {
    if (maxUnits < 0) throw ArgumentError.value(maxUnits);
    if (content.isSourceFree) {
      throw ArgumentError('Emphasis requires actual source text');
    }
    _targets = _EmphasisTargetPreparation(
      projection: content.projection,
      runs: content.runs,
      path: content.path,
      maxUnits: maxUnits,
    );
    if (glyphInput == null) {
      _glyphPreparation = ForumBodyEmphasisGlyphPreparation(content: content);
    }
  }
  final int maxUnits;
  ForumBodyEmphasisGlyphPreparation? _glyphPreparation;
  ForumBodyEmphasisGlyphInput? _glyphInput;
  _EmphasisTargetPreparation? _targets;
  ForumBodyEmphasisTextInput? _result;
  bool _closed = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_closed) throw StateError('Emphasis text preparation is retired');
    var used = 0;
    try {
      while (used < maxParts && !isReady) {
        if (_glyphInput == null) {
          final glyphs = _glyphPreparation!;
          used += glyphs.advance(maxParts: maxParts - used);
          if (glyphs.isReady) {
            _glyphInput = glyphs.takeInput();
            _glyphPreparation = null;
          }
        } else {
          used += _targets!.advance(maxParts: maxParts - used);
          if (_targets!.isReady) {
            _result = ForumBodyEmphasisTextInput._(
              _glyphInput!,
              _targets!.takeUnits(),
            );
            _glyphInput = null;
            _targets = null;
          }
        }
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    }
  }

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
    _targets?.close();
    _targets = null;
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
