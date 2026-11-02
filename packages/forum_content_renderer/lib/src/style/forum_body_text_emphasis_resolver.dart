import 'package:flutter/painting.dart' show Color;
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import 'forum_body_text_emphasis.dart';

typedef _Mark = ({
  ForumBodyEmphasisShape shape,
  ForumBodyEmphasisFill fill,
  String? custom,
});
const _none = (
  shape: ForumBodyEmphasisShape.none,
  fill: ForumBodyEmphasisFill.filled,
  custom: null,
);
typedef ForumBodyEmphasisColorParser =
    ({Color? color, bool unsupported, bool transparent}) Function(String raw);

/// Separate longhands cascade against the shorthand using the parsed source
/// order/importance. Position inherits independently and is never reset by it.
ForumBodyTextEmphasis resolveForumBodyTextEmphasis({
  required ForumBodyAuthorStyle declarations,
  required ForumBodyTextEmphasis inherited,
  required ForumBodyEmphasisColorParser parseColor,
  required void Function(String property, String value) onUnsupported,
  bool rubyAnnotation = false,
}) {
  // CSS Ruby's UA shorthand `rtc, rt { text-emphasis: none }` resets style
  // and color, but not position. Explicit author inherit still sees the real
  // parent, rather than this lower-priority default.
  final fallback = rubyAnnotation
      ? ForumBodyTextEmphasis(
          side: inherited.side,
          verticalSide: inherited.verticalSide,
        )
      : inherited;
  // Most reader nodes only inherit this value. Avoid allocating cascade jobs,
  // maps and a new computed object on that ordinary style-resolution path.
  if (!declarations.declarations.any(
    (declaration) => const {
      'text-emphasis',
      'text-emphasis-style',
      'text-emphasis-color',
      'text-emphasis-position',
    }.contains(declaration.property),
  )) {
    return fallback;
  }
  final inheritedMark = (
    shape: inherited.shape,
    fill: inherited.fill,
    custom: inherited.customMark,
  );
  var mark = rubyAnnotation ? _none : inheritedMark;
  Color? color = fallback.color;
  var side = inherited.side;
  var vertical = inherited.verticalSide;
  final parsed = <ForumBodyDeclaration, ({_Mark mark, Color? color})?>{};
  final reported = <ForumBodyDeclaration>{};
  void report(ForumBodyDeclaration declaration) {
    if (reported.add(declaration)) {
      onUnsupported(declaration.property, declaration.value);
    }
  }

  ({_Mark mark, Color? color})? shorthand(
    ForumBodyDeclaration declaration,
  ) => parsed.putIfAbsent(declaration, () {
    final raw = declaration.value.trim();
    final keyword = raw.toLowerCase();
    if (keyword == 'inherit' || keyword == 'unset') {
      return (mark: inheritedMark, color: inherited.color);
    }
    if (keyword == 'initial') return (mark: _none, color: null);
    final terms = _terms(raw);
    if (terms == null || terms.isEmpty) return null;
    final shapeTerms = <String>[];
    Color? actualColor;
    var foundColor = false;
    for (final term in terms) {
      if (_isMarkTerm(term)) {
        shapeTerms.add(term);
        continue;
      }
      if (foundColor) return null;
      if (term.toLowerCase() == 'currentcolor') {
        actualColor = null;
      } else {
        final value = parseColor(term.toLowerCase());
        if (value.unsupported || (!value.transparent && value.color == null)) {
          return null;
        }
        actualColor = value.transparent ? const Color(0x00000000) : value.color;
      }
      foundColor = true;
    }
    final actualMark = shapeTerms.isEmpty
        ? _none
        : _parseMark(shapeTerms.join(' '));
    return actualMark == null ? null : (mark: actualMark, color: actualColor);
  });
  for (final markDeclaration in _cascade(declarations, {
    'text-emphasis',
    'text-emphasis-style',
  })) {
    final raw = markDeclaration.value.trim();
    final keyword = raw.toLowerCase();
    final value = markDeclaration.property == 'text-emphasis'
        ? shorthand(markDeclaration)?.mark
        : keyword == 'inherit' || keyword == 'unset'
        ? inheritedMark
        : keyword == 'initial'
        ? _none
        : _parseMark(raw);
    if (value == null) {
      report(markDeclaration);
    } else {
      mark = value;
      break;
    }
  }
  for (final colorDeclaration in _cascade(declarations, {
    'text-emphasis',
    'text-emphasis-color',
  })) {
    final raw = colorDeclaration.value.trim();
    final keyword = raw.toLowerCase();
    if (colorDeclaration.property == 'text-emphasis') {
      final value = shorthand(colorDeclaration);
      if (value == null) {
        report(colorDeclaration);
        continue;
      } else {
        color = value.color;
      }
    } else if (keyword == 'initial' || keyword == 'currentcolor') {
      color = null;
    } else if (keyword == 'inherit' || keyword == 'unset') {
      color = inherited.color;
    } else {
      final value = parseColor(keyword);
      if (value.unsupported || (!value.transparent && value.color == null)) {
        report(colorDeclaration);
        continue;
      } else {
        color = value.transparent ? const Color(0x00000000) : value.color;
      }
    }
    break;
  }
  for (final declaration in _cascade(declarations, {
    'text-emphasis-position',
  })) {
    final rawPosition = declaration.value;
    final value = rawPosition.trim().toLowerCase();
    if (value == 'initial') {
      side = ForumBodyEmphasisSide.over;
      vertical = ForumBodyEmphasisVerticalSide.right;
    } else if (value != 'inherit' && value != 'unset') {
      final terms = value.split(RegExp(r'\s+'));
      final over = terms.contains('over'), under = terms.contains('under');
      final right = terms.contains('right'), left = terms.contains('left');
      if (over == under ||
          right && left ||
          terms.toSet().length != terms.length ||
          terms.any(
            (part) => !const {'over', 'under', 'right', 'left'}.contains(part),
          )) {
        onUnsupported('text-emphasis-position', rawPosition);
        continue;
      } else {
        side = under ? ForumBodyEmphasisSide.under : ForumBodyEmphasisSide.over;
        vertical = left
            ? ForumBodyEmphasisVerticalSide.left
            : ForumBodyEmphasisVerticalSide.right;
      }
    }
    break;
  }
  return ForumBodyTextEmphasis(
    shape: mark.shape,
    fill: mark.fill,
    customMark: mark.custom,
    color: color,
    side: side,
    verticalSide: vertical,
  );
}

/// Invalid declarations cannot hide a valid earlier value, even when the
/// invalid declaration is important. Each longhand chooses its own winner.
Iterable<ForumBodyDeclaration> _cascade(
  ForumBodyAuthorStyle style,
  Set<String> names,
) sync* {
  for (final important in [true, false]) {
    for (var i = style.declarations.length - 1; i >= 0; i--) {
      final declaration = style.declarations[i];
      if (declaration.important == important &&
          names.contains(declaration.property)) {
        yield declaration;
      }
    }
  }
}

bool _isMarkTerm(String raw) =>
    raw.startsWith('"') ||
    raw.startsWith("'") ||
    const {
      'none',
      'filled',
      'open',
      'dot',
      'circle',
      'double-circle',
      'triangle',
      'sesame',
    }.contains(raw.toLowerCase());

_Mark? _parseMark(String raw) {
  if (raw.startsWith('"') || raw.startsWith("'")) {
    final value = _string(raw);
    if (value == null || value.length > 512) return null;
    // Reuse the core's whole-grapheme boundaries without inventing a forum
    // source context or adding another Unicode segmentation implementation.
    final text = HtmlDisplayTextProjection.build([
      HtmlDisplayTextRun(
        text: value,
        sourceRuneStart: 0,
        whiteSpace: HtmlDisplayWhiteSpace.pre,
      ),
    ]);
    if (text.graphemeRanges(startUtf16: 0, endUtf16: text.text.length).length >
        1) {
      return null;
    }
    return (
      shape: ForumBodyEmphasisShape.custom,
      fill: ForumBodyEmphasisFill.filled,
      custom: value,
    );
  }
  final parts = raw.toLowerCase().split(RegExp(r'\s+'));
  if (parts.length == 1 && parts.single == 'none') return _none;
  ForumBodyEmphasisShape? shape;
  ForumBodyEmphasisFill? fill;
  for (final part in parts) {
    if (part == 'filled' || part == 'open') {
      if (fill != null) return null;
      fill = part == 'open'
          ? ForumBodyEmphasisFill.open
          : ForumBodyEmphasisFill.filled;
    } else {
      if (shape != null) return null;
      shape = switch (part) {
        'dot' => ForumBodyEmphasisShape.dot,
        'circle' => ForumBodyEmphasisShape.circle,
        'double-circle' => ForumBodyEmphasisShape.doubleCircle,
        'triangle' => ForumBodyEmphasisShape.triangle,
        'sesame' => ForumBodyEmphasisShape.sesame,
        _ => null,
      };
      if (shape == null) return null;
    }
  }
  return (
    shape: shape ?? ForumBodyEmphasisShape.circle,
    fill: fill ?? ForumBodyEmphasisFill.filled,
    custom: null,
  );
}

/// Split only this finite declaration grammar; quoted marks and color
/// functions remain intact, including embedded whitespace and CSS escapes.
List<String>? _terms(String raw) {
  final result = <String>[];
  var start = 0, depth = 0;
  int? quote;
  for (var i = 0; i < raw.length; i++) {
    final unit = raw.codeUnitAt(i);
    if (unit == 92) {
      i++;
      continue;
    }
    if (quote != null) {
      if (unit == quote) quote = null;
      continue;
    }
    if (unit == 34 || unit == 39) {
      quote = unit;
      continue;
    }
    if (unit == 40) {
      depth++;
    } else if (unit == 41) {
      if (--depth < 0) return null;
    } else if (depth == 0 && _space(unit)) {
      if (i > start) result.add(raw.substring(start, i));
      start = i + 1;
    }
  }
  if (quote != null || depth != 0) return null;
  if (start < raw.length) result.add(raw.substring(start));
  return result;
}

String? _string(String raw) {
  if (raw.length < 2 || raw.codeUnitAt(raw.length - 1) != raw.codeUnitAt(0)) {
    return null;
  }
  final output = StringBuffer();
  for (var i = 1; i < raw.length - 1; i++) {
    final unit = raw.codeUnitAt(i);
    if (unit == raw.codeUnitAt(0) || unit == 10 || unit == 13 || unit == 12) {
      return null;
    }
    if (unit != 92) {
      output.writeCharCode(unit);
      continue;
    }
    if (++i == raw.length - 1) return null;
    final escaped = raw.codeUnitAt(i);
    if (escaped == 10 || escaped == 12) continue;
    if (escaped == 13) {
      if (i + 1 < raw.length - 1 && raw.codeUnitAt(i + 1) == 10) i++;
      continue;
    }
    if (!_hex(escaped)) {
      output.writeCharCode(escaped);
      continue;
    }
    final start = i;
    while (i + 1 < raw.length - 1 &&
        i - start < 5 &&
        _hex(raw.codeUnitAt(i + 1))) {
      i++;
    }
    final scalar = int.parse(raw.substring(start, i + 1), radix: 16);
    output.writeCharCode(
      scalar == 0 || scalar > 0x10ffff || scalar >= 0xd800 && scalar <= 0xdfff
          ? 0xfffd
          : scalar,
    );
    if (i + 1 < raw.length - 1 && _space(raw.codeUnitAt(i + 1))) {
      i++;
      if (raw.codeUnitAt(i) == 13 &&
          i + 1 < raw.length - 1 &&
          raw.codeUnitAt(i + 1) == 10) {
        i++;
      }
    }
  }
  return output.toString();
}

bool _hex(int value) =>
    value >= 48 && value <= 57 ||
    value >= 65 && value <= 70 ||
    value >= 97 && value <= 102;
bool _space(int value) => const {9, 10, 12, 13, 32}.contains(value);
