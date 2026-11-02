import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/style/forum_body_text_emphasis_resolver.dart';

({ForumBodyTextEmphasis value, List<(String, String)> issues}) _parse(
  List<ForumBodyDeclaration> declarations, {
  ForumBodyTextEmphasis inherited = const ForumBodyTextEmphasis(),
}) {
  final issues = <(String, String)>[];
  final value = resolveForumBodyTextEmphasis(
    declarations: ForumBodyAuthorStyle(declarations: declarations),
    inherited: inherited,
    parseColor: const CsslibAuthorColorParser().parseValue,
    onUnsupported: (property, value) => issues.add((property, value)),
  );
  return (value: value, issues: issues);
}

ForumBodyDeclaration _decl(
  String property,
  String value, [
  bool important = false,
]) => ForumBodyDeclaration(property, value, important);

ForumBodyReaderStyle _reader({ForumBodyStylePolicy? policy}) =>
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        height: 1,
        color: Color(0xff123456),
      ),
      fontRevision: 'emphasis-contract',
      linkColor: const Color(0xff0000ff),
      policy: policy,
    );
({ForumBodyDocument document, ForumBodyStyleResult styles}) _resolve(
  String html, {
  ForumBodyReaderStyle? reader,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'emphasis',
    conversionIdentity: 'none',
  );
  return (
    document: document,
    styles: const ForumBodyStyleResolver().resolve(
      document,
      reader ?? _reader(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unrelated declarations reuse the exact inherited emphasis value', () {
    const inherited = ForumBodyTextEmphasis(
      shape: ForumBodyEmphasisShape.dot,
      side: ForumBodyEmphasisSide.under,
      color: Color(0xffabcdef),
    );
    expect(_parse([], inherited: inherited).value, same(inherited));
    expect(
      _parse([
        _decl('color', 'red'),
        _decl('font-size', '30px'),
      ], inherited: inherited).value,
      same(inherited),
    );
  });
  for (final (name, filled, open) in [
    ('dot', '•', '◦'),
    ('circle', '●', '○'),
    ('double-circle', '◉', '◎'),
    ('triangle', '▲', '△'),
    ('sesame', '﹅', '﹆'),
  ]) {
    for (final (raw, expected) in [
      (name, filled),
      ('open $name', open),
      ('$name filled', filled),
      ('$name OPEN', open),
    ]) {
      test('computed author mark $raw retains its glyph', () {
        final result = _parse([_decl('text-emphasis-style', raw)]);
        expect(result.issues, isEmpty);
        expect(result.value.mark, expected);
        expect(result.value.isEnabled, isTrue);
        expect(result.value, _parse([_decl('text-emphasis-style', raw)]).value);
        expect(
          result.value.hashCode,
          _parse([_decl('text-emphasis-style', raw)]).value.hashCode,
        );
      });
    }
  }
  test('fill-only horizontal marks compute to circles', () {
    expect(_parse([_decl('text-emphasis-style', 'open')]).value.mark, '○');
    expect(_parse([_decl('text-emphasis-style', 'filled')]).value.mark, '●');
  });
  for (final (raw, mark) in [
    ("'X'", 'X'),
    ("'e\u0301'", 'e\u0301'),
    ("'👨‍👩‍👧‍👦'", '👨‍👩‍👧‍👦'),
    (r"'\25b2 '", '▲'),
    (r"'\58'", 'X'),
    (r"'\0'", '\ufffd'),
    (r"'\110000'", '\ufffd'),
    (r"'\d800'", '\ufffd'),
    (r"'\''", "'"),
  ]) {
    test('custom mark preserves one complete grapheme $raw', () {
      final result = _parse([_decl('text-emphasis-style', raw)]);
      expect(result.issues, isEmpty);
      expect(result.value.shape, ForumBodyEmphasisShape.custom);
      expect(result.value.mark, mark);
    });
  }
  test('empty custom mark stays represented and disables visible marks', () {
    final value = _parse([_decl('text-emphasis-style', "''")]).value;
    expect(value.shape, ForumBodyEmphasisShape.custom);
    expect(value.mark, '');
    expect(value.isEnabled, isFalse);
  });
  test('shorthand resets style/color and preserves independent position', () {
    const inherited = ForumBodyTextEmphasis(
      shape: ForumBodyEmphasisShape.dot,
      color: Color(0xff0000ff),
      side: ForumBodyEmphasisSide.under,
      verticalSide: ForumBodyEmphasisVerticalSide.left,
    );
    final value = _parse([
      _decl('text-emphasis', 'open triangle'),
    ], inherited: inherited).value;
    expect(value.mark, '△');
    expect(value.color, isNull);
    expect(value.side, ForumBodyEmphasisSide.under);
    expect(value.verticalSide, ForumBodyEmphasisVerticalSide.left);
    final colorOnly = _parse([
      _decl('text-emphasis', 'red'),
    ], inherited: inherited).value;
    expect(colorOnly.isEnabled, isFalse);
    expect(colorOnly.color, const Color(0xffff0000));
  });
  test('importance and source order select each longhand independently', () {
    final value = _parse([
      _decl('text-emphasis', 'blue open triangle', true),
      _decl('text-emphasis-style', 'sesame'),
      _decl('text-emphasis-color', 'red', true),
    ]).value;
    expect(value.mark, '△');
    expect(value.color, const Color(0xffff0000));
    expect(
      _parse([
        _decl('text-emphasis-style', 'open'),
        _decl('text-emphasis', 'filled dot'),
      ]).value.mark,
      '•',
    );
  });
  test(
    'invalid declarations cannot erase earlier valid longhands or shorthand',
    () {
      final result = _parse([
        _decl('text-emphasis', 'open triangle blue'),
        _decl('text-emphasis-style', 'circle dot', true),
        _decl('text-emphasis-color', 'var(--color)', true),
        _decl('text-emphasis-position', 'under left'),
        _decl('text-emphasis-position', 'over under', true),
      ]);
      expect(result.value.mark, '△');
      expect(result.value.color, const Color(0xff0000ff));
      expect(result.value.side, ForumBodyEmphasisSide.under);
      expect(result.value.verticalSide, ForumBodyEmphasisVerticalSide.left);
      expect(result.issues, hasLength(3));
      final other = _parse([
        _decl('text-emphasis-style', 'open sesame'),
        _decl('text-emphasis-color', 'green'),
        _decl('text-emphasis', 'none dot', true),
      ]);
      expect(other.value.mark, '﹆');
      expect(other.value.color, const Color(0xff008000));
      expect(other.issues, [('text-emphasis', 'none dot')]);
    },
  );
  for (final raw in [
    'rgb(20, 40, 60) open circle',
    'open circle rgb(20, 40, 60)',
    'circle rgb(20, 40, 60) open',
  ]) {
    test('color functions remain one shorthand component: $raw', () {
      final result = _parse([_decl('text-emphasis', raw)]);
      expect(result.issues, isEmpty);
      expect(result.value.color, const Color(0xff14283c));
      expect(result.value.mark, '○');
    });
  }
  for (final keyword in ['inherit', 'unset']) {
    test('CSS-wide $keyword inherits all independent values', () {
      const inherited = ForumBodyTextEmphasis(
        shape: ForumBodyEmphasisShape.sesame,
        fill: ForumBodyEmphasisFill.open,
        color: Color(0xffabcdef),
        side: ForumBodyEmphasisSide.under,
        verticalSide: ForumBodyEmphasisVerticalSide.left,
      );
      expect(
        _parse([
          _decl('text-emphasis', keyword),
          _decl('text-emphasis-position', keyword),
        ], inherited: inherited).value,
        inherited,
      );
      expect(
        _parse([
          _decl('text-emphasis-style', keyword),
          _decl('text-emphasis-color', keyword),
        ], inherited: inherited).value,
        inherited,
      );
    });
  }
  for (final raw in [
    'filled filled',
    'none open',
    'circle dot',
    "'AB'",
    "'x",
    'sideways',
    'var(--mark)',
  ]) {
    test('unsupported mark reports its actual declaration: $raw', () {
      final result = _parse([_decl('text-emphasis', raw)]);
      expect(result.issues, [('text-emphasis', raw)]);
      expect(result.value.isEnabled, isFalse);
    });
  }
  for (final raw in [
    'left',
    'over under',
    'under right left',
    'over over',
    'under sideways',
  ]) {
    test('invalid position remains diagnosed: $raw', () {
      final result = _parse([_decl('text-emphasis-position', raw)]);
      expect(result.issues, [('text-emphasis-position', raw)]);
    });
  }
  test(
    'actual IR preserves quoted mark case, inheritance, reader policy and position',
    () {
      final css = const HtmlEscape(
        HtmlEscapeMode.attribute,
      ).convert('text-emphasis: "X" red; text-emphasis-position: under left');
      final result = _resolve(
        '<div style="$css"><span style="color:blue">A</span>'
        '<ruby>B<rt>b</rt></ruby><span style="text-emphasis:none">C</span></div>',
        reader: _reader(
          policy: ForumBodyStylePolicy({
            ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.forceBody,
          }),
        ),
      );
      expect(result.styles.issues, isEmpty);
      final elements = result.document.descendants
          .whereType<ForumBodyElement>()
          .toList();
      final values = [
        for (final node in elements)
          result.styles.byPath[node.path]!.textEmphasis,
      ];
      expect(values.first.mark, 'X');
      expect(
        values.take(values.length - 1).every((v) => v.mark == 'X'),
        isTrue,
      );
      expect(values.first.side, ForumBodyEmphasisSide.under);
      expect(values.first.verticalSide, ForumBodyEmphasisVerticalSide.left);
      expect(values.last.isEnabled, isFalse);
      expect(values.last.color, isNull);
      expect(result.document.sourceText, 'ABbC');
    },
  );
  test(
    'native paragraph and band explicitly reject active marks before shaping',
    () {
      final result = _resolve('<p style="text-emphasis:dot">A</p>');
      final input = const ForumBodyParagraphContentBuilder().build(
        document: result.document,
        styles: result.styles,
        path: '0',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 20,
      );
      try {
        final failure = throwsA(
          isA<ForumBodyParagraphLayoutException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphLayoutFailure.emphasis,
          ),
        );
        expect(() => cache.acquire(content: input, width: 100), failure);
        final intrinsic = const ForumBodyParagraphContentBuilder().build(
          document: result.document,
          styles: result.styles,
          path: '0',
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        );
        final band = ForumBodyTextBandContent(contexts: [intrinsic]);
        expect(
          () => cache.acquireBandChild(content: band, childIndex: 0),
          failure,
        );
        final inline = ForumBodyInlineSpanContent.compose(
          identity: input.identity,
          path: input.path,
          fontRevision: input.fontRevision,
          styleRevision: input.styleRevision,
          style: input.style,
          contexts: [input],
          atomicRanges: const [],
        );
        expect(
          () => cache.acquireInline(
            content: inline,
            width: 100,
            dimensions: const [],
          ),
          failure,
        );
        expect(cache.layoutBuildCount, 0);
        expect(cache.activeLeases, 0);
      } finally {
        cache.close();
      }
    },
  );
  test(
    'inactive emphasis color and empty string do not block ordinary native text',
    () {
      for (final css in [
        'text-emphasis-color:red',
        "text-emphasis-style:''",
        'text-emphasis:none',
      ]) {
        final result = _resolve('<p style="$css">A</p>');
        final input = const ForumBodyParagraphContentBuilder().build(
          document: result.document,
          styles: result.styles,
          path: '0',
        );
        final cache = ForumBodyParagraphCache(
          maxEntries: 8,
          maxEstimatedBytes: 1 << 20,
        );
        try {
          final lease = cache.acquire(content: input, width: 100);
          expect(lease.layout.lines, hasLength(1));
          lease.release();
        } finally {
          cache.close();
        }
      }
    },
  );
}
