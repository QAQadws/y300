/// Comic title analysis, leading metadata and normalization in pure Dart.
///
/// Search keywords keep the existing 18-rune limit; cleanBookName remains whole.
/// Subject metadata mapping, search requests and provider assembly belong to
/// the consuming application. This library does not expose petitparser types.
library;

export 'src/comic_title_analysis.dart' show ComicTitleAnalysis;
export 'src/comic_title_analyzer.dart'
    show ComicTitleAnalyzer, PetitComicTitleAnalyzer;
export 'src/comic_title_grammar.dart'
    show ComicLeadingBracketToken, ComicLeadingMetadata, ComicTitleGrammar;
export 'src/comic_title_number_parser.dart' show ComicTitleNumberParser;
export 'src/comic_title_rules.dart' show ComicTitleRules;
