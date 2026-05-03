import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';

/// Normalized context for one post parsing unit.
class ParsedPostContext {
  const ParsedPostContext({
    required this.tid,
    required this.fid,
    required this.subject,
    required this.authorUid,
    required this.isFirst,
    required this.messageHtml,
    required this.messageText,
  });

  final String tid;
  final String fid;
  final String subject;
  final String authorUid;
  final bool isFirst;
  final String messageHtml;
  final String messageText;
}

enum ParsedLinkKind {
  episode,
  catalog,
  external,
  unknown,
}

class ParsedAnchorFeatures {
  const ParsedAnchorFeatures({
    required this.containsOrdinal,
    required this.containsSpecial,
    required this.containsCatalog,
  });

  final bool containsOrdinal;
  final bool containsSpecial;
  final bool containsCatalog;
}

class ParsedAnchor {
  const ParsedAnchor({
    required this.rawHref,
    required this.normalizedUrl,
    required this.text,
    required this.linkKind,
    required this.features,
    this.tidCandidate,
  });

  final String rawHref;
  final String normalizedUrl;
  final String text;
  final String? tidCandidate;
  final ParsedLinkKind linkKind;
  final ParsedAnchorFeatures features;
}

enum EpisodeSourceType {
  threadHtml,
  viewthreadQuery,
}

class EpisodeLinkCandidate {
  const EpisodeLinkCandidate({
    required this.tid,
    required this.url,
    required this.titleRaw,
    required this.titleNormalized,
    required this.sourceType,
    required this.confidence,
    required this.position,
    this.groupId,
  });

  final String tid;
  final String url;
  final String titleRaw;
  final String titleNormalized;
  final EpisodeSourceType sourceType;
  final double confidence;
  final int position;
  final int? groupId;
}

class EpisodeExtractionResult {
  const EpisodeExtractionResult({
    required this.episodes,
    required this.catalogLinks,
    required this.nextHopCandidates,
    required this.debugSignals,
  });

  final List<EpisodeLinkCandidate> episodes;
  final List<String> catalogLinks;
  final List<String> nextHopCandidates;
  final List<ComicParsingSignal> debugSignals;
}

