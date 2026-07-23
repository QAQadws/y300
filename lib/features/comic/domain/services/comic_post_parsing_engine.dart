import 'dart:collection';

import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';
import 'package:y300/features/comic/domain/models/comic_post_parsing_models.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

/// Phase-1 parser engine:
/// - Normalize anchors from post html
/// - Extract semantic features
/// - Apply pluggable rules
/// - Output de-duplicated episode candidates with debug signals
class ComicPostParsingEngine {
  ComicPostParsingEngine({
    List<ComicPostParsingRule>? rules,
    ForumPostDomExtractor? domExtractor,
    YamiboTagPageParsing tagPageParsing = const YamiboTagPageParsing(),
  }) : _domExtractor = domExtractor ?? const ForumPostDomExtractor(),
       _tagPageParsing = tagPageParsing,
       _rules =
           rules ??
           <ComicPostParsingRule>[
             CatalogRule(),
             EpisodeStrongRule(),
             EpisodeClusterRule(),
             RejectRule(),
           ];

  static final RegExp _ordinalPattern = RegExp(
    r'(^\d+(\.\d+)?\s*[话話].*|^\d+(\.\d+)?$|第\s*.+\s*[话話])',
    caseSensitive: false,
  );
  static final RegExp _specialPattern = RegExp(
    r'(特典|附录|番外)',
    caseSensitive: false,
  );
  static final RegExp _catalogTextPattern = RegExp(
    r'(目录|目錄|索引|合集|合輯|电梯|電梯|catalog|contents)',
    caseSensitive: false,
  );

  final ForumPostDomExtractor _domExtractor;
  final YamiboTagPageParsing _tagPageParsing;
  final List<ComicPostParsingRule> _rules;

  EpisodeExtractionResult parse({required String messageHtml}) {
    final debugSignals = <ComicParsingSignal>[];
    final anchors = _extractAnchors(
      messageHtml: messageHtml,
      debugSignals: debugSignals,
    );
    final clusteredGroupIds = _detectSequentialGroups(anchors);
    final drafts = <_EpisodeDraft>[];
    final catalogLinks = <String>{};
    final nextHopCandidates = <String>{};
    final rejectedUrls = <String>{};

    for (var i = 0; i < anchors.length; i++) {
      final anchor = anchors[i];
      final ruleContext = RuleContext(
        index: i,
        anchor: anchor,
        groupId: clusteredGroupIds[i],
      );
      for (final rule in _rules) {
        final decision = rule.apply(ruleContext);
        if (decision == null) {
          continue;
        }
        debugSignals.add(
          ComicParsingSignal(stage: 'rule', message: decision.debugMessage),
        );
        switch (decision.action) {
          case RuleAction.addCatalog:
            catalogLinks.add(anchor.normalizedUrl);
            break;
          case RuleAction.addEpisode:
            final tid = anchor.tidCandidate;
            if (tid != null) {
              drafts.add(
                _EpisodeDraft(
                  tid: tid,
                  url: anchor.normalizedUrl,
                  titleRaw: anchor.text,
                  sourceType: anchor.normalizedUrl.contains('thread-')
                      ? EpisodeSourceType.threadHtml
                      : EpisodeSourceType.viewthreadQuery,
                  confidence: decision.confidence,
                  position: i,
                  groupId: clusteredGroupIds[i],
                ),
              );
            }
            break;
          case RuleAction.addNextHop:
            nextHopCandidates.add(anchor.normalizedUrl);
            break;
          case RuleAction.reject:
            rejectedUrls.add(anchor.normalizedUrl);
            break;
        }
      }
    }

    final episodes = _deduplicateAndSort(drafts, rejectedUrls: rejectedUrls);
    return EpisodeExtractionResult(
      episodes: episodes,
      catalogLinks: catalogLinks.toList(growable: false),
      nextHopCandidates: nextHopCandidates.toList(growable: false),
      debugSignals: debugSignals,
    );
  }

  List<ParsedAnchor> _extractAnchors({
    required String messageHtml,
    required List<ComicParsingSignal> debugSignals,
  }) {
    final extracted = _domExtractor.extractAnchors(messageHtml);
    debugSignals.add(
      ComicParsingSignal(
        stage: 'anchor',
        message: 'raw anchors=${extracted.length}',
      ),
    );
    final anchors = <ParsedAnchor>[];

    for (final anchor in extracted) {
      final text = anchor.text;
      final containsCatalog = _isCatalogAnchor(
        text: text,
        normalizedUrl: anchor.normalizedUrl,
      );
      final features = ParsedAnchorFeatures(
        containsOrdinal: _ordinalPattern.hasMatch(text),
        containsSpecial: _specialPattern.hasMatch(text),
        containsCatalog: containsCatalog,
      );
      final kind = _inferKind(anchor.normalizedUrl, features, anchor.tid);
      anchors.add(
        ParsedAnchor(
          rawHref: anchor.rawHref,
          normalizedUrl: anchor.normalizedUrl,
          text: text,
          tidCandidate: anchor.tid,
          linkKind: kind,
          features: features,
        ),
      );
    }
    return anchors;
  }

  bool _isCatalogAnchor({required String text, required String normalizedUrl}) {
    return _catalogTextPattern.hasMatch(text.trim()) &&
        _tagPageParsing.isTagCatalogUrl(normalizedUrl);
  }

  List<int?> _detectSequentialGroups(List<ParsedAnchor> anchors) {
    final groupIds = List<int?>.filled(anchors.length, null);
    int currentGroupId = 0;
    int runStart = 0;

    while (runStart < anchors.length) {
      int runEnd = runStart;
      while (runEnd + 1 < anchors.length &&
          _isLikelySequentialLink(anchors[runEnd], anchors[runEnd + 1])) {
        runEnd += 1;
      }
      final runLength = runEnd - runStart + 1;
      if (runLength >= 3) {
        currentGroupId += 1;
        for (var i = runStart; i <= runEnd; i++) {
          groupIds[i] = currentGroupId;
        }
      }
      runStart = runEnd + 1;
    }
    return groupIds;
  }

  bool _isLikelySequentialLink(ParsedAnchor a, ParsedAnchor b) {
    if (a.tidCandidate == null || b.tidCandidate == null) {
      return false;
    }
    final aNum = int.tryParse(a.text);
    final bNum = int.tryParse(b.text);
    if (aNum != null && bNum != null && (bNum - aNum).abs() <= 2) {
      return true;
    }
    return a.features.containsOrdinal && b.features.containsOrdinal;
  }

  List<EpisodeLinkCandidate> _deduplicateAndSort(
    List<_EpisodeDraft> drafts, {
    required Set<String> rejectedUrls,
  }) {
    // Preserve message order as the single source of truth for chapter order.
    // We still deduplicate by tid, but we keep the earliest appearance to
    // guarantee deterministic "message order -> detail page reverse order".
    final bestByTid = HashMap<String, _EpisodeDraft>();
    for (final draft in drafts) {
      if (rejectedUrls.contains(draft.url)) {
        continue;
      }
      final current = bestByTid[draft.tid];
      if (current == null) {
        bestByTid[draft.tid] = draft;
        continue;
      }
      if (draft.position < current.position) {
        bestByTid[draft.tid] = draft;
      }
    }

    final list = bestByTid.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    return list
        .map(
          (e) => EpisodeLinkCandidate(
            tid: e.tid,
            url: e.url,
            titleRaw: e.titleRaw,
            titleNormalized: e.titleRaw.trim(),
            sourceType: e.sourceType,
            confidence: e.confidence,
            position: e.position,
            groupId: e.groupId,
          ),
        )
        .toList(growable: false);
  }

  ParsedLinkKind _inferKind(
    String url,
    ParsedAnchorFeatures features,
    String? tid,
  ) {
    if (features.containsCatalog) {
      return ParsedLinkKind.catalog;
    }
    if (tid != null) {
      return ParsedLinkKind.episode;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return ParsedLinkKind.external;
    }
    return ParsedLinkKind.unknown;
  }
}

class _EpisodeDraft {
  const _EpisodeDraft({
    required this.tid,
    required this.url,
    required this.titleRaw,
    required this.sourceType,
    required this.confidence,
    required this.position,
    this.groupId,
  });

  final String tid;
  final String url;
  final String titleRaw;
  final EpisodeSourceType sourceType;
  final double confidence;
  final int position;
  final int? groupId;
}

enum RuleAction { addCatalog, addEpisode, addNextHop, reject }

class RuleDecision {
  const RuleDecision({
    required this.action,
    required this.confidence,
    required this.debugMessage,
  });

  final RuleAction action;
  final double confidence;
  final String debugMessage;
}

class RuleContext {
  const RuleContext({
    required this.index,
    required this.anchor,
    required this.groupId,
  });

  final int index;
  final ParsedAnchor anchor;
  final int? groupId;
}

abstract class ComicPostParsingRule {
  RuleDecision? apply(RuleContext context);
}

class CatalogRule implements ComicPostParsingRule {
  @override
  RuleDecision? apply(RuleContext context) {
    if (!context.anchor.features.containsCatalog) {
      return null;
    }
    return RuleDecision(
      action: RuleAction.addCatalog,
      confidence: 1,
      debugMessage: 'catalog hit url=${context.anchor.normalizedUrl}',
    );
  }
}

class EpisodeStrongRule implements ComicPostParsingRule {
  @override
  RuleDecision? apply(RuleContext context) {
    final anchor = context.anchor;
    if (anchor.tidCandidate == null) {
      return null;
    }
    // Keep backward compatibility: catalog links still count as episode links
    // in existing parser behavior/tests, while being marked as catalog too.
    if (anchor.features.containsCatalog) {
      return RuleDecision(
        action: RuleAction.addEpisode,
        confidence: 0.8,
        debugMessage:
            'EpisodeStrongRule catalog-compatible tid=${anchor.tidCandidate}',
      );
    }
    if (anchor.features.containsOrdinal || anchor.features.containsSpecial) {
      return RuleDecision(
        action: RuleAction.addEpisode,
        confidence: anchor.features.containsOrdinal ? 1 : 0.92,
        debugMessage: 'EpisodeStrongRule hit tid=${anchor.tidCandidate}',
      );
    }
    return null;
  }
}

class EpisodeClusterRule implements ComicPostParsingRule {
  @override
  RuleDecision? apply(RuleContext context) {
    if (context.anchor.tidCandidate == null || context.groupId == null) {
      return null;
    }
    return RuleDecision(
      action: RuleAction.addEpisode,
      confidence: 0.85,
      debugMessage:
          'EpisodeClusterRule hit group=${context.groupId} tid=${context.anchor.tidCandidate}',
    );
  }
}

class RejectRule implements ComicPostParsingRule {
  @override
  RuleDecision? apply(RuleContext context) {
    if (context.anchor.tidCandidate != null) {
      return null;
    }
    return RuleDecision(
      action: RuleAction.reject,
      confidence: 1,
      debugMessage: 'RejectRule rejected url=${context.anchor.normalizedUrl}',
    );
  }
}
