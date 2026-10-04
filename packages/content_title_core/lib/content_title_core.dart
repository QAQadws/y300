/// Independent comic and novel title policies in pure Dart.
///
/// Comic search keywords keep the 18-rune limit; cleanBookName remains whole.
/// Novel title cleaning and chapter headings preserve their own rules.
/// Subject mapping, HTML preparation, search and provider assembly belong to
/// the consuming application. Test fixtures are outside this public API.
library;

export 'src/comic/comic_title_analysis.dart' show ComicTitleAnalysis;
export 'src/comic/comic_title_analyzer.dart'
    show ComicTitleAnalyzer, PetitComicTitleAnalyzer;
export 'src/comic/comic_title_grammar.dart'
    show ComicLeadingBracketToken, ComicLeadingMetadata, ComicTitleGrammar;
export 'src/comic/comic_title_number_parser.dart' show ComicTitleNumberParser;
export 'src/comic/comic_title_rules.dart' show ComicTitleRules;
export 'src/novel/novel_title_sanitizer.dart'
    show DefaultNovelTitleSanitizer, NovelTitleSanitizer;
export 'src/novel/novel_chapter_title_policy.dart'
    show
        FirstMeaningfulSentenceNovelChapterTitlePolicy,
        NovelChapterTitlePolicy;
