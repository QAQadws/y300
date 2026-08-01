import 'package:petitparser/petitparser.dart';

import 'comic_title_rules.dart';

class ComicLeadingBracketToken {
  const ComicLeadingBracketToken({required this.raw, required this.value});

  final String raw;
  final String value;
}

class ComicLeadingMetadata {
  const ComicLeadingMetadata({required this.tokens, required this.remainder});

  final List<ComicLeadingBracketToken> tokens;
  final String remainder;
}

class ComicTitleGrammar {
  const ComicTitleGrammar();

  static final Parser<String> _openBracketParser = anyOf(
    ComicTitleRules.leadingBracketOpenCharacters,
  ).flatten();
  static final Parser<String> _closeBracketParser = anyOf(
    ComicTitleRules.leadingBracketCloseCharacters,
  ).flatten();
  static final Parser<ComicLeadingBracketToken> _leadingBracketTokenParser =
      (whitespace().star().flatten() &
              _openBracketParser &
              any().starLazy(_closeBracketParser).flatten() &
              _closeBracketParser)
          .map((value) {
            final parts = value as List<Object?>;
            final raw =
                '${parts[0] as String}${parts[1] as String}${parts[2] as String}${parts[3] as String}';
            return ComicLeadingBracketToken(
              raw: raw,
              value: (parts[2] as String).trim(),
            );
          });

  ComicLeadingMetadata parseLeadingMetadata(String input) {
    final tokens = <ComicLeadingBracketToken>[];
    var cursor = input;
    while (true) {
      final result = _leadingBracketTokenParser.parse(cursor);
      if (result is Failure) {
        break;
      }
      final token = result.value;
      if (token.value.isNotEmpty) {
        tokens.add(token);
      }
      cursor = cursor.substring(result.position);
    }
    return ComicLeadingMetadata(tokens: tokens, remainder: cursor.trimLeft());
  }
}
