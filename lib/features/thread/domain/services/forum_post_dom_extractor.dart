import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';
import 'package:y300/features/thread/domain/services/forum_thread_url_parser.dart';

class ForumPostAnchor {
  const ForumPostAnchor({
    required this.rawHref,
    required this.normalizedUrl,
    required this.text,
    required this.position,
    this.tid,
  });

  final String rawHref;
  final String normalizedUrl;
  final String text;
  final int position;
  final String? tid;
}

/// DOM based extractor for Discuz post fragments.
///
/// The extractor intentionally exposes neutral primitives (anchors, image
/// sources, plain text) so comic, novel, and later favorite sync rules can
/// share one HTML normalization path without sharing business semantics.
class ForumPostDomExtractor {
  const ForumPostDomExtractor({
    ForumThreadUrlParser? urlParser,
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlParser = urlParser ?? const ForumThreadUrlParser(),
       _urlResolver = urlResolver;

  final ForumThreadUrlParser _urlParser;
  final SiteUrlResolver _urlResolver;

  static const Set<String> _paragraphBlockTags = <String>{
    'p',
    'div',
    'section',
    'article',
    'li',
  };

  List<ForumPostAnchor> extractAnchors(String html) {
    final fragment = html_parser.parseFragment(html);
    final anchors = <ForumPostAnchor>[];
    final nodes = fragment.querySelectorAll('a');
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final rawHref = (node.attributes['href'] ?? '').trim();
      if (rawHref.isEmpty) {
        continue;
      }
      final String? normalizedUrl;
      try {
        normalizedUrl = _urlParser.normalizeHref(rawHref);
      } on FormatException {
        continue;
      }
      if (normalizedUrl == null) {
        continue;
      }
      final String? tid;
      try {
        tid = _urlParser.extractTid(normalizedUrl);
      } on FormatException {
        continue;
      }
      anchors.add(
        ForumPostAnchor(
          rawHref: rawHref,
          normalizedUrl: normalizedUrl,
          text: _normalizeText(node.text),
          position: index,
          tid: tid,
        ),
      );
    }
    return anchors;
  }

  List<String> extractThreadTids(String html) {
    final tids = <String>[];
    final seen = <String>{};
    for (final anchor in extractAnchors(html)) {
      final tid = anchor.tid;
      if (tid != null && seen.add(tid)) {
        tids.add(tid);
      }
    }
    return tids;
  }

  List<String> extractImageSources(
    String html, {
    bool ignoreForumChromeImages = true,
  }) {
    return DefaultForumImageSourcePipeline.collectDomImageSources(
      html,
      urlResolver: _urlResolver,
      includeForumChrome: !ignoreForumChromeImages,
    ).map((source) => source.normalizedUrl).toList(growable: false);
  }

  String? normalizeImageSource(String src) =>
      DefaultForumImageSourcePipeline.normalizeImageSource(
        src,
        urlResolver: _urlResolver,
      );

  String extractPlainText(String html) {
    final fragment = html_parser.parseFragment(_preserveTextBreaks(html));
    return _normalizeText(fragment.text ?? '');
  }

  List<String> extractParagraphTexts(String html) {
    final fragment = html_parser.parseFragment(html);
    final paragraphNodes = fragment.querySelectorAll(
      'p, div, section, article, li',
    );
    final paragraphs = <String>[];
    final seen = <String>{};
    for (final node in paragraphNodes) {
      if (_hasNestedParagraphBlock(node)) {
        continue;
      }
      final text = _normalizeText(node.text);
      if (text.isNotEmpty && seen.add(text)) {
        paragraphs.add(text);
      }
    }
    if (paragraphs.isNotEmpty) {
      return paragraphs;
    }
    final plainText = extractPlainText(html);
    return plainText.isEmpty
        ? const <String>[]
        : plainText
              .split(RegExp(r'\n{1,}'))
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();
  }

  List<String> extractHeadingTexts(String html) {
    final fragment = html_parser.parseFragment(html);
    return fragment
        .querySelectorAll('h1, h2, h3, strong, b, font[size]')
        .map((node) => _normalizeText(node.text))
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
  }

  bool _hasNestedParagraphBlock(html_dom.Element node) {
    return node.children.any((child) {
      final localName = child.localName?.toLowerCase();
      if (localName != null && _paragraphBlockTags.contains(localName)) {
        return true;
      }
      return _hasNestedParagraphBlock(child);
    });
  }

  String _normalizeText(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\r\n|\r'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  String _preserveTextBreaks(String html) {
    // Discuz mobile HTML often uses <br> instead of block tags. Preserving
    // those breaks keeps novel heading lines such as "001 xxx" from merging
    // with the following paragraph during title extraction.
    return html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  }
}
