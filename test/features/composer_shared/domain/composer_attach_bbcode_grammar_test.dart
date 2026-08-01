import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';

void main() {
  const grammar = ComposerAttachBbCodeGrammar();

  group('isLegalCode', () {
    test('accepts a numeric aid regardless of tag case', () {
      expect(grammar.isLegalCode('[attach]1626084[/attach]'), isTrue);
      expect(grammar.isLegalCode('[ATTACH]12[/Attach]'), isTrue);
    });

    test('rejects non-numeric, empty and padded aids', () {
      expect(grammar.isLegalCode('[attach]abc[/attach]'), isFalse);
      expect(grammar.isLegalCode('[attach][/attach]'), isFalse);
      expect(grammar.isLegalCode('[attach] 12 [/attach]'), isFalse);
      expect(grammar.isLegalCode('[attach]12'), isFalse);
      expect(grammar.isLegalCode('前缀[attach]12[/attach]'), isFalse);
    });
  });

  test('isLegalAid only accepts digits', () {
    expect(grammar.isLegalAid('1626084'), isTrue);
    expect(grammar.isLegalAid(''), isFalse);
    expect(grammar.isLegalAid('12a'), isFalse);
    expect(grammar.isLegalAid(' 12'), isFalse);
  });

  test('codeFor and aidOf round-trip', () {
    expect(grammar.codeFor('1626084'), '[attach]1626084[/attach]');
    expect(grammar.codeFor('  1626084  '), '[attach]1626084[/attach]');
    expect(grammar.aidOf(grammar.codeFor('1626084')), '1626084');
  });

  test('aidOf returns null for illegal codes', () {
    expect(grammar.aidOf('[attach]abc[/attach]'), isNull);
    expect(grammar.aidOf('[attach]12[/attach]额外'), isNull);
  });

  group('scan', () {
    test('reports every legal token with its span', () {
      const source = '前[attach]12[/attach]中[ATTACH]345[/attach]后';
      final matches = grammar.scan(source);

      expect(matches, hasLength(2));
      expect(matches.first.aid, '12');
      expect(
        source.substring(matches.first.start, matches.first.end),
        '[attach]12[/attach]',
      );
      expect(matches.last.aid, '345');
      expect(matches.last.length, '[ATTACH]345[/attach]'.length);
    });

    test('skips illegal tokens', () {
      final matches = grammar.scan('[attach]abc[/attach][attach]7[/attach]');

      expect(matches, hasLength(1));
      expect(matches.single.aid, '7');
    });

    test('returns nothing for an empty source', () {
      expect(grammar.scan(''), isEmpty);
    });
  });

  test('tokenPatternSource composes into larger patterns without groups', () {
    final pattern = RegExp(
      '${ComposerAttachBbCodeGrammar.tokenPatternSource}|X',
      caseSensitive: false,
    );

    expect(
      pattern.allMatches('[attach]9[/attach]X').map((match) => match.group(0)),
      ['[attach]9[/attach]', 'X'],
    );
  });
}
