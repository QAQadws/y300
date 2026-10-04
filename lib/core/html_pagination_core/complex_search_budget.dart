import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

/// Renderer workload proxies, not a guarantee of synchronous layout latency.
final class HtmlComplexSearchBudget {
  const HtmlComplexSearchBudget({
    this.maxProbeCount = 12,
    this.initialWindowGraphemes = 64,
    this.maxWindowGraphemes = 1024,
    this.maxCandidateHtmlCodeUnits = 8192,
    this.maxCandidateDomNodes = 256,
    this.maxOversizedMinimumHtmlCodeUnits = 32768,
    this.maxOversizedMinimumDomNodes = 1024,
    this.workSliceDuration = const Duration(milliseconds: 3),
  }) : assert(maxProbeCount >= 4),
       assert(initialWindowGraphemes > 0),
       assert(maxWindowGraphemes >= initialWindowGraphemes),
       assert(maxCandidateHtmlCodeUnits > 0),
       assert(maxCandidateDomNodes > 0),
       assert(maxOversizedMinimumHtmlCodeUnits >= maxCandidateHtmlCodeUnits),
       assert(maxOversizedMinimumDomNodes >= maxCandidateDomNodes);

  final int maxProbeCount;
  final int initialWindowGraphemes;
  final int maxWindowGraphemes;
  final int maxCandidateHtmlCodeUnits;
  final int maxCandidateDomNodes;
  final int maxOversizedMinimumHtmlCodeUnits;
  final int maxOversizedMinimumDomNodes;
  final Duration workSliceDuration;

  bool allowsCandidate(
    String html,
    int domNodeCount, {
    bool oversizedMinimum = false,
  }) =>
      html.length <=
          (oversizedMinimum
              ? maxOversizedMinimumHtmlCodeUnits
              : maxCandidateHtmlCodeUnits) &&
      domNodeCount <=
          (oversizedMinimum
              ? maxOversizedMinimumDomNodes
              : maxCandidateDomNodes);

  /// Used once for a page buffer or atomic fallback, never per sliced probe.
  static int countDomNodes(String html) {
    if (html.isEmpty) return 0;
    final pending = <dom.Node>[...parser.parseFragment(html).nodes];
    var count = 0;
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      count += 1;
      pending.addAll(node.nodes);
    }
    return count;
  }
}
