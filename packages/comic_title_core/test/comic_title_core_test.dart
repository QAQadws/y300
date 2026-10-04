import 'package:comic_title_core/comic_title_core.dart';
import 'package:test/test.dart';

void main() {
  group('ComicTitleNumberParser', () {
    const parser = ComicTitleNumberParser();

    test('parses supported numeral forms', () {
      const cases = <String, double>{
        ' １２．５　': 12.5,
        '〇': 0,
        '两百零三': 203,
        '兩千三百四十五': 2345,
        '二〇二六': 2026,
        'ix': 9,
        'Ⅻ': 12,
        '②': 2,
        '⑳': 20,
        '3.125': 3.125,
      };

      for (final entry in cases.entries) {
        expect(parser.parseNumber(entry.key), entry.value, reason: entry.key);
      }
    });

    test('returns null for empty and non-number input', () {
      for (final source in ['', ' \t ', '12x', '一半', '1..2']) {
        expect(parser.parseNumber(source), isNull, reason: source);
      }
    });
  });

  group('ComicTitleGrammar', () {
    const grammar = ComicTitleGrammar();

    test('retains raw prefix tokens and leaves bracket text in the body', () {
      final ComicLeadingMetadata result = grammar.parseLeadingMetadata(
        ' \t[ first ]  【second】 \nremaining [body] text',
      );
      final List<ComicLeadingBracketToken> tokens = result.tokens;

      expect(tokens.map((token) => token.value), ['first', 'second']);
      expect(tokens.map((token) => token.raw), [' \t[ first ]', '  【second】']);
      expect(result.remainder, 'remaining [body] text');
    });

    test('consumes empty prefixes without emitting empty metadata', () {
      final result = grammar.parseLeadingMetadata('[ ]【】[last] body');

      expect(result.tokens, hasLength(1));
      expect(result.tokens.single.value, 'last');
      expect(result.tokens.single.raw, '[last]');
      expect(result.remainder, 'body');
    });

    test('stops at unclosed prefixes and ordinary body text', () {
      final unclosed = grammar.parseLeadingMetadata('[first] 【unclosed body');

      expect(unclosed.tokens.map((token) => token.value), ['first']);
      expect(unclosed.remainder, '【unclosed body');
      for (final source in ['[unclosed body', 'plain [later] body']) {
        final result = grammar.parseLeadingMetadata(source);
        expect(result.tokens, isEmpty, reason: source);
        expect(result.remainder, source, reason: source);
      }
    });
  });

  group('ComicTitleRules', () {
    test(
      'normalizes variants and repeated amp entities without case folding',
      () {
        const source = ' \tＣａｓｅ　＃１２．５：Ａ～Ｂ &amp;amp; Friends\n ';
        final normalized = ComicTitleRules.normalizeForMatching(source);

        expect(normalized, 'Case #12.5:A~B & Friends');
        expect(ComicTitleRules.normalizeForMatching(normalized), normalized);
        expect(ComicTitleRules.normalizeForMatching('Ａa 漫畫'), 'Aa 漫畫');
        expect(
          ComicTitleRules.normalizeHtmlEntities('&lt; &AMP;'),
          '&lt; &AMP;',
        );
      },
    );

    test('recognizes metadata hints and preserves outer tilde decoration', () {
      expect(ComicTitleRules.looksLikeTranslationGroup('ScAn'), isTrue);
      expect(ComicTitleRules.looksLikeTranslationGroup('author'), isFalse);
      expect(ComicTitleRules.isComiketToken('ＣＯＭＩＫＥＴ １２３'), isTrue);
      expect(ComicTitleRules.isComiketToken('COMIKET 12 extra'), isFalse);
      expect(ComicTitleRules.extractAuthorHint('作者： author / tail'), 'author');
      expect(ComicTitleRules.extractAuthorHint('body'), isNull);
      expect(ComicTitleRules.trimOuterSeparators(' --:~body~？！ '), '~body~');
    });
  });

  group('public analyzer contract', () {
    const ComicTitleAnalyzer analyzer = PetitComicTitleAnalyzer();

    test('blank source returns the public empty analysis', () {
      for (final source in ['', ' \t\n\r　 ']) {
        final ComicTitleAnalysis result = analyzer.analyze(source);

        expect(result, same(ComicTitleAnalysis.empty));
        expect(result.rawTitle, isEmpty);
        expect(result.cleanBookName, isEmpty);
        expect(result.searchKeyword, isEmpty);
        expect(result.authorPrefix, isNull);
        expect(result.episodeLabel, isNull);
        expect(result.chapterNumber, isNull);
        expect(result.possibleChapterNumbers, isEmpty);
      }
    });

    test('generated Unicode names retain full text and clip at 18 runes', () {
      for (var rotation = 0; rotation < 3; rotation += 1) {
        for (final length in [1, 17, 18, 19, 32, 64]) {
          final book = _generatedBook(length, rotation: rotation);
          final result = analyzer.analyze(' \t$book\n ');

          expect(result.rawTitle, book);
          expect(result.cleanBookName, book);
          expect(result.searchKeyword.runes, book.runes.take(18));
          expect(result.authorPrefix, isNull);
          expect(result.episodeLabel, isNull);
          expect(result.chapterNumber, isNull);
          expect(result.possibleChapterNumbers, isEmpty);
        }
      }
    });

    test('successive generated analyses do not mutate earlier results', () {
      final results = <ComicTitleAnalysis>[];
      for (var chapter = 1; chapter <= 6; chapter += 1) {
        final book = _generatedBook(24, rotation: chapter);
        results.add(analyzer.analyze('$book 第$chapter话'));
        analyzer.analyze('');
      }

      for (var index = 0; index < results.length; index += 1) {
        final chapter = index + 1;
        final book = _generatedBook(24, rotation: chapter);
        final result = results[index];
        expect(result.rawTitle, '$book 第$chapter话');
        expect(result.cleanBookName, book);
        expect(result.chapterNumber, chapter.toDouble());
        expect(result.possibleChapterNumbers, [chapter.toDouble()]);
        expect(result.episodeLabel, '第$chapter话');
      }
    });

    test(
      'accepts explicit grammar and number parser through the public API',
      () {
        const ComicTitleGrammar grammar = _InjectedGrammar();
        const numberParser = ComicTitleNumberParser();
        const ComicTitleAnalyzer configured = PetitComicTitleAnalyzer(
          grammar: grammar,
          numberParser: numberParser,
        );
        final book = _generatedBook(23);
        final fullwidthNumber = String.fromCharCodes(
          '12'.runes.map((rune) => rune + 0xFEE0),
        );
        final result = configured.analyze('$book 第$fullwidthNumber话');

        expect(result.cleanBookName, book);
        expect(result.authorPrefix, 'injected');
        expect(result.chapterNumber, 12);
        expect(result.possibleChapterNumbers, [12]);
      },
    );
  });
}

String _generatedBook(int length, {int rotation = 0}) {
  const alphabet = [0x7532, 0x4E59, 0x1F642, 0x1F680, 0x3042, 0xD55C, 0x1D11E];
  return String.fromCharCodes([
    for (var index = 0; index < length; index += 1)
      alphabet[(index + rotation) % alphabet.length],
  ]);
}

class _InjectedGrammar extends ComicTitleGrammar {
  const _InjectedGrammar();

  @override
  ComicLeadingMetadata parseLeadingMetadata(String input) {
    return ComicLeadingMetadata(
      tokens: const [
        ComicLeadingBracketToken(raw: '[injected]', value: 'injected'),
      ],
      remainder: input,
    );
  }
}
