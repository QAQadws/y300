import 'dart:collection';

import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';
import 'package:y300/features/comic/domain/models/comic_post_parsing_models.dart';

/// Phase-1 parser engine:
/// - Normalize anchors from post html
/// - Extract semantic features
/// - Apply pluggable rules
/// - Output de-duplicated episode candidates with debug signals
class ComicPostParsingEngine {
  ComicPostParsingEngine({
    List<ComicPostParsingRule>? rules,
  }) : _rules = rules ??
            <ComicPostParsingRule>[
              CatalogRule(),
              EpisodeStrongRule(),
              EpisodeClusterRule(),
              RejectRule(),
            ];

  static const String _yamiboOrigin = 'https://bbs.yamibo.com/';
  static final RegExp _threadPathPattern = RegExp(r'thread-(\d+)-\d+-\d+\.html', caseSensitive: false);
  static final RegExp _forumViewThreadPattern = RegExp(
    r'forum\.php\?[^#]*\bmod=viewthread\b[^#]*\btid=(\d+)',
    caseSensitive: false,
  );
  static final RegExp _damagedTidPattern = RegExp(r'(^|[?&;])tid=(\d+)(?:[&#]|$)', caseSensitive: false);
  static final RegExp _ordinalPattern = RegExp(r'(^\d+(\.\d+)?$|第\s*.+\s*话)', caseSensitive: false);
  static final RegExp _specialPattern = RegExp(r'(特典|附录|番外)', caseSensitive: false);

  final List<ComicPostParsingRule> _rules;

  EpisodeExtractionResult parse({
    required String messageHtml,
  }) {
    final debugSignals = <ComicParsingSignal>[];
    final anchors = _extractAnchors(messageHtml: messageHtml, debugSignals: debugSignals);
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
        debugSignals.add(ComicParsingSignal(stage: 'rule', message: decision.debugMessage));
        switch (decision.action) {
          case RuleAction.addCatalog:
            catalogLinks.add(anchor.normalizedUrl);
            break;
          case RuleAction.addEpisode:
            final tid = _extractTid(anchor.normalizedUrl);
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
    final document = html_parser.parseFragment(messageHtml);
    final nodes = document.querySelectorAll('a');
    debugSignals.add(ComicParsingSignal(stage: 'anchor', message: 'raw anchors=${nodes.length}'));
    final anchors = <ParsedAnchor>[];

    for (final node in nodes) {
      final rawHref = (node.attributes['href'] ?? '').trim();
      if (rawHref.isEmpty) {
        continue;
      }
      final normalized = _normalizeUrl(rawHref);
      if (normalized == null) {
        debugSignals.add(ComicParsingSignal(stage: 'anchor', message: 'reject href=$rawHref'));
        continue;
      }
      final text = node.text.trim();
      final features = ParsedAnchorFeatures(
        containsOrdinal: _ordinalPattern.hasMatch(text),
        containsSpecial: _specialPattern.hasMatch(text),
        containsCatalog: text.contains('目录'),
      );
      final tid = _extractTid(normalized);
      final kind = _inferKind(normalized, features);
      anchors.add(
        ParsedAnchor(
          rawHref: rawHref,
          normalizedUrl: normalized,
          text: text,
          tidCandidate: tid,
          linkKind: kind,
          features: features,
        ),
      );
    }
    return anchors;
  }

  List<int?> _detectSequentialGroups(List<ParsedAnchor> anchors) {
    final groupIds = List<int?>.filled(anchors.length, null);
    int currentGroupId = 0;
    int runStart = 0;

    while (runStart < anchors.length) {
      int runEnd = runStart;
      while (runEnd + 1 < anchors.length && _isLikelySequentialLink(anchors[runEnd], anchors[runEnd + 1])) {
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

    final list = bestByTid.values.toList()..sort((a, b) => a.position.compareTo(b.position));

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

  ParsedLinkKind _inferKind(String url, ParsedAnchorFeatures features) {
    if (features.containsCatalog) {
      return ParsedLinkKind.catalog;
    }
    if (_extractTid(url) != null) {
      return ParsedLinkKind.episode;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return ParsedLinkKind.external;
    }
    return ParsedLinkKind.unknown;
  }

  String? _normalizeUrl(String href) {
    var decoded = href.trim();
    while (decoded.contains('&amp;')) {
      decoded = decoded.replaceAll('&amp;', '&');
    }
    if (decoded.startsWith(';tid=') || decoded.startsWith('tid=')) {
      final damagedTid = _extractTidFromDamagedHref(decoded);
      if (damagedTid != null) {
        return 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$damagedTid';
      }
    }
    final uri = Uri.tryParse(decoded);
    if (uri == null) {
      return null;
    }
    final effectiveUri = uri.hasScheme ? uri : Uri.parse(_yamiboOrigin).resolveUri(uri);
    final isThreadHtml = _threadPathPattern.hasMatch(effectiveUri.path);
    final isForumViewThread = effectiveUri.path.toLowerCase().endsWith('forum.php') &&
        effectiveUri.queryParameters['mod']?.toLowerCase() == 'viewthread' &&
        (effectiveUri.queryParameters['tid']?.isNotEmpty ?? false);

    String? normalizedQuery;
    if (isForumViewThread) {
      final mod = effectiveUri.queryParameters['mod'];
      final tid = effectiveUri.queryParameters['tid'];
      final fromuid = effectiveUri.queryParameters['fromuid'];
      final queryPairs = <String>[
        if (mod != null) 'mod=$mod',
        if (tid != null) 'tid=$tid',
        if (fromuid != null && fromuid.isNotEmpty) 'fromuid=$fromuid',
      ];
      normalizedQuery = queryPairs.isEmpty ? null : queryPairs.join('&');
    } else if (isThreadHtml) {
      normalizedQuery = null;
    } else {
      normalizedQuery = effectiveUri.hasQuery ? effectiveUri.query : null;
    }

    return Uri(
      scheme: effectiveUri.scheme,
      userInfo: effectiveUri.userInfo,
      host: effectiveUri.host,
      port: effectiveUri.hasPort ? effectiveUri.port : null,
      path: effectiveUri.path,
      query: normalizedQuery,
    ).toString();
  }

  String? _extractTid(String normalizedUrl) {
    final threadMatch = _threadPathPattern.firstMatch(normalizedUrl);
    if (threadMatch != null) {
      return threadMatch.group(1);
    }
    final viewthreadMatch = _forumViewThreadPattern.firstMatch(normalizedUrl);
    if (viewthreadMatch != null) {
      return viewthreadMatch.group(1);
    }
    return _extractTidFromDamagedHref(normalizedUrl);
  }

  String? _extractTidFromDamagedHref(String href) {
    final match = _damagedTidPattern.firstMatch(href);
    return match?.group(2);
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

enum RuleAction {
  addCatalog,
  addEpisode,
  addNextHop,
  reject,
}

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
        debugMessage: 'EpisodeStrongRule catalog-compatible tid=${anchor.tidCandidate}',
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
      debugMessage: 'EpisodeClusterRule hit group=${context.groupId} tid=${context.anchor.tidCandidate}',
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
