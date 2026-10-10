import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';

/// Local, source-preserving eligibility for the selected-text open action.
/// The UI separately verifies selection boundaries against its source text;
/// a syntactically valid URL prefix cannot prove completeness on its own.
final class ForumSelectedLinkPolicy {
  const ForumSelectedLinkPolicy({
    ForumHttpTextLinkDetector detector = const ForumHttpTextLinkDetector(),
    YamiboForumLinkResolver resolver = const YamiboForumLinkResolver(),
  }) : _detector = detector,
       _resolver = resolver;

  final ForumHttpTextLinkDetector _detector;
  final YamiboForumLinkResolver _resolver;

  String? resolve(String selectedText) {
    final scan = _detector.detect(selectedText);
    // Count every occurrence before site filtering or deduplication. An
    // external link or a repeated identical URL makes the choice ambiguous.
    if (scan.isLimited || scan.links.length != 1) return null;
    final link = scan.links.single;
    return _resolver.resolveBrowsable(link.text) == null ? null : link.text;
  }
}

/// Evidence prepared once from the copy page's complete visible source text.
/// It deliberately does not project selection offsets into HTML or renderer
/// coordinates. Ambiguous prefix selections are rejected rather than repaired.
final class ForumSelectedLinkSource {
  const ForumSelectedLinkSource._(this._links, this._isLimited);

  factory ForumSelectedLinkSource.fromText(String sourceText) {
    if (sourceText.isEmpty) {
      return const ForumSelectedLinkSource._({}, false);
    }
    final scan = const ForumHttpTextLinkDetector().detect(
      sourceText,
      maxInputLength: sourceText.length,
      maxCandidates: sourceText.length,
    );
    return ForumSelectedLinkSource._(
      Set.unmodifiable(scan.links.map((link) => link.text)),
      scan.isLimited,
    );
  }

  /// Source evidence keeps literal hard line breaks, including those inside
  /// preformatted/code text. Copy exporters may collapse them and accidentally
  /// certify a URL prefix. Block boundaries also keep unrelated text apart;
  /// this is conservative evidence, not a projection of rendered selections.
  factory ForumSelectedLinkSource.fromHtml(String sourceHtml) {
    final fragment = html_parser.parseFragment(sourceHtml);
    final text = StringBuffer();
    final pending = <(html_dom.Node, bool)>[(fragment, false)];
    const boundaries = {
      'address',
      'article',
      'aside',
      'blockquote',
      'br',
      'dd',
      'div',
      'dl',
      'dt',
      'fieldset',
      'figcaption',
      'figure',
      'footer',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'header',
      'hr',
      'img',
      'li',
      'main',
      'nav',
      'ol',
      'p',
      'pre',
      'section',
      'table',
      'td',
      'th',
      'tr',
      'ul',
    };
    while (pending.isNotEmpty) {
      final (node, closing) = pending.removeLast();
      if (closing) {
        text.write('\n');
      } else if (node is html_dom.Text) {
        text.write(node.text);
      } else {
        final tag = node is html_dom.Element ? node.localName : null;
        if (tag == 'script' || tag == 'style') continue;
        if (boundaries.contains(tag)) {
          text.write('\n');
          pending.add((node, true));
        }
        for (final child in node.nodes.reversed) {
          pending.add((child, false));
        }
      }
    }
    return ForumSelectedLinkSource.fromText(text.toString());
  }

  final Set<String> _links;
  final bool _isLimited;

  bool confirms(String url) {
    if (_isLimited || !_links.contains(url)) return false;
    // Without a public mapping from selection endpoints into the source, an
    // identical base URL elsewhere cannot prove this is not a longer URL's
    // selected prefix. Keep the normal copy menu for that ambiguous case.
    return !_links.any(
      (link) => link.length > url.length && link.startsWith(url),
    );
  }
}
