class ComicTitleAnalysis {
  const ComicTitleAnalysis({
    required this.rawTitle,
    required this.cleanBookName,
    required this.searchKeyword,
    this.authorPrefix,
    this.episodeLabel,
    this.chapterNumber,
    this.isChapterRange = false,
    this.possibleChapterNumbers = const <double>[],
  });

  final String rawTitle;
  final String cleanBookName;
  final String searchKeyword;
  final String? authorPrefix;
  final String? episodeLabel;
  final double? chapterNumber;

  /// The parsed label denotes a range, rather than alternative chapter numbers.
  final bool isChapterRange;
  final List<double> possibleChapterNumbers;

  static const ComicTitleAnalysis empty = ComicTitleAnalysis(
    rawTitle: '',
    cleanBookName: '',
    searchKeyword: '',
  );
}
