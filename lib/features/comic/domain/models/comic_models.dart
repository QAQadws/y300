class ComicCandidateInfo {
  const ComicCandidateInfo({
    required this.isCandidate,
    required this.score,
    required this.reasons,
  });

  final bool isCandidate;
  final int score;
  final List<String> reasons;

  static const ComicCandidateInfo notCandidate = ComicCandidateInfo(
    isCandidate: false,
    score: 0,
    reasons: <String>[],
  );
}

class ComicEpisodeLink {
  const ComicEpisodeLink({
    required this.url,
    required this.rawText,
    this.episodeTitle,
  });

  final String url;
  final String rawText;
  final String? episodeTitle;
}

class ParsedComicPost {
  const ParsedComicPost({
    required this.imageUrls,
    required this.episodeLinks,
    required this.plainTextSummary,
    this.catalogUrl,
    this.inferredAuthor,
    this.subjectMetadata,
  });

  final List<String> imageUrls;
  final List<ComicEpisodeLink> episodeLinks;
  final String plainTextSummary;
  final String? catalogUrl;
  final String? inferredAuthor;
  final ComicSubjectMetadata? subjectMetadata;

  ParsedComicPost copyWith({
    List<String>? imageUrls,
    List<ComicEpisodeLink>? episodeLinks,
    String? plainTextSummary,
    String? catalogUrl,
    String? inferredAuthor,
    ComicSubjectMetadata? subjectMetadata,
  }) {
    return ParsedComicPost(
      imageUrls: imageUrls ?? this.imageUrls,
      episodeLinks: episodeLinks ?? this.episodeLinks,
      plainTextSummary: plainTextSummary ?? this.plainTextSummary,
      catalogUrl: catalogUrl ?? this.catalogUrl,
      inferredAuthor: inferredAuthor ?? this.inferredAuthor,
      subjectMetadata: subjectMetadata ?? this.subjectMetadata,
    );
  }

  static const ParsedComicPost empty = ParsedComicPost(
    imageUrls: <String>[],
    episodeLinks: <ComicEpisodeLink>[],
    plainTextSummary: '',
  );
}

class ComicSubjectMetadata {
  const ComicSubjectMetadata({
    required this.normalizedTitle,
    this.translationGroup,
    this.inferredAuthor,
    this.episodeLabel,
  });

  final String normalizedTitle;
  final String? translationGroup;
  final String? inferredAuthor;
  final String? episodeLabel;
}
