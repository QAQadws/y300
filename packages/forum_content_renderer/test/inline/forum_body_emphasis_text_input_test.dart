import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyParagraphContent _html(String html, {String css = ''}) {
  final document = const ForumBodyParser().parse(
    html: '<p style="text-emphasis:dot;white-space:pre-wrap;$css">$html</p>',
    sourceId: 'emphasis-units',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontSize: 20, color: Color(0xff123456)),
      fontRevision: 'emphasis-units',
      linkColor: const Color(0xff0000ff),
    ),
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: styles,
    path: '0',
    layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
  );
}

ForumBodyParagraphContent _text(String text, {String css = ''}) =>
    _html(const HtmlEscape(HtmlEscapeMode.element).convert(text), css: css);

ForumBodyEmphasisTextInput _prepare(
  ForumBodyParagraphContent content, {
  int maxParts = 3,
  int maxUnits = 512,
}) {
  final preparation = ForumBodyEmphasisTextPreparation(
    content: content,
    maxUnits: maxUnits,
  );
  try {
    var total = 0;
    while (!preparation.isReady) {
      final used = preparation.advance(maxParts: maxParts);
      expect(used, inInclusiveRange(1, maxParts));
      total += used;
      expect(total, lessThan(100000));
    }
    expect(preparation.advance(maxParts: 1), 0);
    return preparation.takeInput();
  } finally {
    preparation.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final value in [
    '中',
    'あ',
    '각',
    'A',
    '8',
    '٢',
    '𠀀',
    '❤',
    '❤︎',
    '👩‍👩‍👧‍👦',
    '🇨🇳',
    'e\u0301',
    '한',
    '\u0301',
    '\ue000',
  ]) {
    test(
      'one complete eligible unit $value retains actual source and style',
      () {
        final content = _text(value);
        final input = _prepare(content, maxParts: 1);
        expect(input.content, same(content));
        expect(input.units, hasLength(1));
        final unit = input.units.single;
        expect(unit.startUtf16, 0);
        expect(unit.endUtf16, value.length);
        expect(unit.governingUtf16, 0);
        expect(content.runs[unit.runIndex].style.textEmphasis.mark, '•');
        expect(content.projection.text, value);
      },
    );
  }
  for (final value in [
    ',',
    '.',
    '。',
    '、',
    '（',
    '）',
    '…',
    '—',
    '_',
    "'",
    '"',
    '！',
    '¿',
    '«',
    '»',
    '·',
    '*',
    '/',
    '\u{10100}',
    '\u0f0b',
    '\u1361',
  ]) {
    test('ordinary punctuation and word separators are skipped: $value', () {
      expect(_prepare(_text(value)).units, isEmpty);
    });
  }
  for (final rune in const [
    0x20,
    0xa0,
    0x3000,
    0x202f,
    0x2003,
    0x2028,
    0x2029,
    0x09,
    0x0a,
    0x0d,
    0x85,
    0x200b,
    0x200d,
    0x202a,
    0x2066,
    0xad,
    0x0378,
    0x10ffff,
  ]) {
    test(
      'separator/control/unassigned U+${rune.toRadixString(16)} is skipped',
      () {
        expect(_prepare(_text(String.fromCharCode(rune))).units, isEmpty);
      },
    );
  }
  // Named CSS exceptions plus the eight compatibility forms from UnicodeData.
  for (final value in '#%&@§¶؉؊٪‰‱⁊⁋⁓〽﹟﹠﹪﹫＃％＆＠'.runes) {
    test(
      'CSS punctuation exception U+${value.toRadixString(16)} receives mark',
      () {
        expect(_prepare(_text(String.fromCharCode(value))).units, hasLength(1));
      },
    );
  }
  for (final (text, count) in [
    (' \u0301', 1),
    ('\u00a0\u0301', 1),
    ('*\u20e3', 1),
    (',\u20dd', 1),
    (',\u0489', 0),
    ('،\u20dd', 1),
    ('\u06d4\u20dd', 0),
    (',\u0301', 0),
    ('。\ufe0f', 0),
    ('🧑🏽‍💻', 1),
  ]) {
    test('whole-cluster category exceptions for $text', () {
      expect(_prepare(_text(text)).units, hasLength(count));
    });
  }
  test('combining styles do not split a base or override its mark owner', () {
    final input = _prepare(
      _html(
        '<span style="text-emphasis:triangle blue">e</span>'
        '<i style="text-emphasis:none">\u0301</i>'
        '<span style="text-emphasis:none">A</span>'
        '<b style="text-emphasis:circle red">\u0301</b>',
      ),
    );
    expect(input.content.projection.text, 'e\u0301A\u0301');
    expect(input.units, hasLength(1));
    final unit = input.units.single;
    expect((unit.startUtf16, unit.endUtf16), (0, 2));
    final style = input.content.runs[unit.runIndex].style;
    expect(style.textEmphasis.mark, '▲');
    expect(style.textEmphasis.color, const Color(0xff0000ff));
    expect(style.textStyle.fontStyle, isNot(FontStyle.italic));
  });
  test(
    'format prepend belongs to its whole unit but does not own base style',
    () {
      final input = _prepare(
        _html(
          '<span style="text-emphasis:none">\u0600</span>'
          '<span style="text-emphasis:triangle blue">١</span>',
        ),
      );
      expect(input.units, hasLength(1));
      final unit = input.units.single;
      expect((unit.startUtf16, unit.endUtf16, unit.governingUtf16), (0, 2, 1));
      final style = input.content.runs[unit.runIndex].style;
      expect(style.textEmphasis.mark, '▲');
      expect(style.textEmphasis.color, const Color(0xff0000ff));
    },
  );
  test('ZWJ emoji across styled seams remains one original target', () {
    final input = _prepare(_html('<span>👩</span><b>‍👩‍</b><i>👧‍👦</i>'));
    expect(input.units, hasLength(1));
    final unit = input.units.single;
    expect(unit.startUtf16, 0);
    expect(unit.endUtf16, '👩‍👩‍👧‍👦'.length);
    expect(input.content.runs[unit.runIndex].style.strong, isFalse);
  });
  test(
    'hidden visibility keeps decoration layout inputs, display:none has none',
    () {
      final input = _prepare(
        _html(
          '<span style="visibility:hidden">A</span>'
          '<span style="display:none">omitted</span>B',
        ),
      );
      expect(input.content.projection.text, 'AB');
      expect(input.units, hasLength(2));
      expect(
        input.content.runs[input.units.first.runIndex].style.visibilityHidden,
        isTrue,
      );
      expect(
        input.content.runs[input.units.last.runIndex].style.visibilityHidden,
        isFalse,
      );
      expect(input.content.projection.sourceAtUtf16(1).isExact, isFalse);
      expect(
        input.content.projection.sourceAtUtf16(1).sourceRune,
        greaterThan(1),
      );
    },
  );
  test(
    'windows use their actual rebased projection and original source owner',
    () {
      final original = _text('甲e\u0301👩‍👩‍👧‍👦乙');
      final content = original.displayWindow(startUtf16: 1, endUtf16: 3);
      final input = _prepare(content);
      expect(input.content, same(content));
      expect(input.units, hasLength(1));
      expect(
        (input.units.single.startUtf16, input.units.single.endUtf16),
        (0, 2),
      );
      expect(content.projection.sourceAtUtf16(0).sourceRune, 1);
      expect(original.projection.text, '甲e\u0301👩‍👩‍👧‍👦乙');
    },
  );
  test('one huge combining unit yields during scalar scanning', () {
    final text = 'A${'\u0301' * 3000}';
    final content = _text(text);
    final preparation = ForumBodyEmphasisTextPreparation(content: content);
    var calls = 0;
    while (!preparation.isReady) {
      expect(preparation.advance(maxParts: 7), inInclusiveRange(1, 7));
      if (++calls == 100) expect(preparation.isReady, isFalse);
    }
    expect(calls, greaterThan(400));
    final input = preparation.takeInput();
    expect(input.units, hasLength(1));
    expect(input.units.single.endUtf16, text.length);
    expect(content.projection.text, text);
  });
  test('targets and source ownership do not depend on work quantum', () {
    final content = _html(
      '<span>e</span><b>\u0301,</b><i>中。👩‍👩‍👧‍👦</i>'
      '<span style="text-emphasis:none">A</span>％',
    );
    List<Object> snapshot(ForumBodyEmphasisTextInput input) => [
      for (final unit in input.units)
        (unit.startUtf16, unit.endUtf16, unit.governingUtf16, unit.runIndex),
    ];
    final expected = snapshot(_prepare(content, maxParts: 1));
    expect(expected, hasLength(4));
    for (final quantum in [2, 3, 7, 512]) {
      expect(snapshot(_prepare(content, maxParts: quantum)), expected);
    }
  });
  test('ready input is immutable and survives retirement of the builder', () {
    final preparation = ForumBodyEmphasisTextPreparation(content: _text('中A'));
    expect(() => preparation.takeInput(), throwsStateError);
    while (!preparation.isReady) {
      preparation.advance(maxParts: 1);
    }
    final input = preparation.takeInput();
    expect(() => input.units.clear(), throwsUnsupportedError);
    preparation.close();
    expect(input.units, hasLength(2));
    expect(() => preparation.advance(maxParts: 1), throwsStateError);
    expect(() => preparation.takeInput(), throwsStateError);
  });
  test(
    'target budget closes the builder without publishing a partial input',
    () {
      final preparation = ForumBodyEmphasisTextPreparation(
        content: _text('ABC'),
        maxUnits: 2,
      );
      expect(
        () => preparation.advance(maxParts: 100),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphInputFailure.inputLimit,
          ),
        ),
      );
      expect(preparation.isReady, isFalse);
      expect(() => preparation.advance(maxParts: 1), throwsStateError);
      expect(_prepare(_text('ABC'), maxUnits: 3).units, hasLength(3));
      expect(_prepare(_text('...'), maxUnits: 0).units, isEmpty);
    },
  );
  test(
    'cancellation at every source/style phase never yields partial targets',
    () {
      final content = _html('<b>e</b><i>\u0301</i><b>A</b><i>B</i>');
      for (var steps = 0; steps < 17; steps++) {
        final preparation = ForumBodyEmphasisTextPreparation(content: content);
        for (var i = 0; i < steps; i++) {
          preparation.advance(maxParts: 1);
        }
        preparation.close();
        preparation.close();
        expect(preparation.isReady, isFalse);
        expect(() => preparation.takeInput(), throwsStateError);
        expect(() => preparation.advance(maxParts: 1), throwsStateError);
      }
    },
  );
  test('anonymous font struts have no source decoration input', () {
    final original = _text('A');
    final strut = ForumBodyParagraphContent.anonymousInline(
      identity: original.identity,
      fontRevision: original.fontRevision,
      styleRevision: original.styleRevision,
      style: original.style,
    );
    expect(
      () => ForumBodyEmphasisTextPreparation(content: strut),
      throwsArgumentError,
    );
    expect(_prepare(_text('')).units, isEmpty);
    expect(
      () => ForumBodyEmphasisTextPreparation(content: original, maxUnits: -1),
      throwsArgumentError,
    );
    final preparation = ForumBodyEmphasisTextPreparation(content: original);
    expect(() => preparation.advance(maxParts: 0), throwsArgumentError);
    preparation.close();
  });
}
