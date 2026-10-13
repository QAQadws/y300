import 'package:html/dom.dart' as html_dom;

import '../services/forum_http_text_link_detector.dart';
import 'theme/css_inline_style_declarations.dart';
import 'theme/forum_html_theme_context.dart';

/// Links complete text-node URLs without flattening author inline markup.
final class ForumHtmlPlainTextLinkifier {
  const ForumHtmlPlainTextLinkifier({
    ForumHttpTextLinkDetector detector = const ForumHttpTextLinkDetector(),
    CssInlineStyleDeclarationCodec declarationCodec =
        const CssInlineStyleDeclarationCodec(),
  }) : _detector = detector,
       _declarationCodec = declarationCodec;

  final ForumHttpTextLinkDetector _detector;
  final CssInlineStyleDeclarationCodec _declarationCodec;

  static const _inlineTags = <String>{
    'span',
    'font',
    'b',
    'strong',
    'i',
    'em',
    'u',
    's',
    'strike',
    'del',
    'ins',
    'small',
    'big',
    'sub',
    'sup',
    'mark',
    'abbr',
    'cite',
    'q',
    'label',
    'time',
    'wbr',
  };
  static const _excludedTags = <String>{
    'a',
    'code',
    'pre',
    'script',
    'style',
    'template',
    'noscript',
    'textarea',
    'select',
    'button',
  };

  void linkify(
    html_dom.DocumentFragment fragment, {
    required ForumHtmlThemeContext theme,
  }) {
    final run =
        <({html_dom.Text node, int start, int end, String? authorColor})>[];
    var text = StringBuffer();
    String? excludedTail;
    final work = <({html_dom.Node node, bool exit, String? authorColor})>[
      for (final node in fragment.nodes.reversed)
        (node: node, exit: false, authorColor: null),
    ];
    Iterable<html_dom.Node> followingNodes(html_dom.Node? upcoming) sync* {
      if (upcoming != null) yield upcoming;
      for (final event in work.reversed) {
        if (!event.exit) yield event.node;
      }
    }

    void flush({
      html_dom.Node? upcoming,
      bool hardBreak = false,
      String? excludedHead,
      bool unknownExcludedHead = false,
    }) {
      if (run.isEmpty) return;
      final source = text.toString();
      final suffix = hardBreak
          ? _leadingVisibleText(followingNodes(upcoming))
          : null;
      final scanSource = excludedHead != null
          ? '$source$excludedHead'
          : suffix == null
          ? source
          : '$source\n$suffix';
      final result = _detector.detect(
        scanSource,
        // A whole DOM run is available, so neither the input nor the candidate
        // count is truncated. Individual URLs still have a bounded size.
        maxInputLength: scanSource.length,
        maxCandidates: scanSource.length,
      );
      var nodeIndex = 0;
      final byNode =
          <
            html_dom.Text,
            ({List<ForumHttpTextLink> links, String? authorColor})
          >{};
      for (final link in result.links) {
        if (link.end > source.length) break;
        if (unknownExcludedHead && link.end == source.length) continue;
        while (nodeIndex < run.length && run[nodeIndex].end <= link.start) {
          nodeIndex++;
        }
        if (nodeIndex == run.length) break;
        final segment = run[nodeIndex];
        // Inspect the full inline run before deciding: a URL split by author
        // markup is skipped rather than linking only its valid-looking prefix.
        if (link.start < segment.start || link.end > segment.end) continue;
        byNode
            .putIfAbsent(
              segment.node,
              () => (links: [], authorColor: segment.authorColor),
            )
            .links
            .add(
              ForumHttpTextLink(
                start: link.start - segment.start,
                end: link.end - segment.start,
                text: link.text,
                uri: link.uri,
              ),
            );
      }
      for (final entry in byNode.entries) {
        _replaceText(
          entry.key,
          entry.value.links,
          entry.value.authorColor ?? _cssColor(theme),
        );
      }
      run.clear();
      text = StringBuffer();
    }

    // Iterative traversal keeps deeply nested author markup off the call stack.
    while (work.isNotEmpty) {
      final event = work.removeLast();
      final node = event.node;
      if (event.exit) {
        flush(hardBreak: true);
        excludedTail = null;
      } else if (node is html_dom.Text) {
        if (node.data.isEmpty) continue;
        if (run.isEmpty && excludedTail != null) {
          text.write(excludedTail);
          excludedTail = null;
        }
        final start = text.length;
        text.write(node.data);
        run.add((
          node: node,
          start: start,
          end: text.length,
          authorColor: event.authorColor,
        ));
      } else if (node is html_dom.Element) {
        final inspection = _inspectElement(node);
        if (inspection.excluded) {
          final inline = _isInline(node);
          final head = _excludedBoundaryText(node);
          final tail = inline ? _excludedBoundaryText(node, atEnd: true) : null;
          if (inline &&
              head == null &&
              tail == null &&
              _isKnownTextEmpty(node)) {
            // Empty excluded inline markup is no text boundary. Keep both
            // eligible text nodes in one run so a split URL is rejected whole.
            continue;
          }
          // The excluded text is context only, never an eligible output node.
          // Inspecting inline adjacency rejects a URL continued inside code,
          // an existing anchor or hidden markup without linking its prefix.
          flush(
            excludedHead: inline
                ? head
                : head == null
                ? null
                : '\n$head',
            unknownExcludedHead: head == null,
          );
          // An opaque subtree exhausted the bounded inspection. Do not assume
          // its tail provided a separator for a directly adjacent URL.
          excludedTail = inline ? tail ?? 'x' : null;
          continue;
        }
        // Capture inheritance before entering children; sibling events retain
        // their own parent color even when this inline run flushes much later.
        final authorColor = inspection.authorColor ?? event.authorColor;
        final inline = _isInline(node);
        if (!inline) {
          flush(upcoming: node, hardBreak: true);
          excludedTail = null;
          work.add((node: node, exit: true, authorColor: event.authorColor));
        }
        work.addAll([
          for (final child in node.nodes.reversed)
            (node: child, exit: false, authorColor: authorColor),
        ]);
      }
    }
    flush();
  }

  bool _isInline(html_dom.Element element) =>
      _inlineTags.contains(element.localName?.toLowerCase()) ||
      element.localName == 'a' ||
      element.localName == 'code';

  bool _isKnownTextEmpty(html_dom.Element element) {
    final pending = <html_dom.Node>[element];
    for (var inspected = 0; pending.isNotEmpty && inspected < 32; inspected++) {
      final node = pending.removeLast();
      if (node is html_dom.Text && node.data.isNotEmpty) return false;
      if (node.nodes.length > 32) return false;
      pending.addAll(node.nodes);
    }
    // Only a fully inspected subtree can be treated as having no text.
    return pending.isEmpty;
  }

  String? _excludedBoundaryText(
    html_dom.Element element, {
    bool atEnd = false,
  }) {
    final pending = <html_dom.Node>[element];
    for (var inspected = 0; pending.isNotEmpty && inspected < 32; inspected++) {
      final node = pending.removeLast();
      if (node is html_dom.Text && node.data.isNotEmpty) {
        if (node.data.length <= 256) return node.data;
        return atEnd
            ? node.data.substring(node.data.length - 256)
            : node.data.substring(0, 256);
      }
      if (node is html_dom.Element) {
        final children = atEnd ? node.nodes.reversed : node.nodes;
        pending.addAll(children.take(32).toList().reversed);
      }
    }
    return null;
  }

  ({bool excluded, String? authorColor}) _inspectElement(
    html_dom.Element element,
  ) {
    if (_isExcludedWithoutStyle(element)) {
      return (excluded: true, authorColor: null);
    }
    // Visibility already needs these declarations. Reuse them for inheritance
    // instead of reparsing every ancestor of each text node with a detected URL.
    final style = _elementStyle(element);
    return (
      excluded: _isExcludedByStyle(element, style),
      authorColor:
          style?.effectiveDeclaration({'color'})?.value ??
          element.attributes['color'],
    );
  }

  CssInlineStyleDeclarationList? _elementStyle(html_dom.Element element) {
    final source = element.attributes['style'];
    return source == null ? null : _declarationCodec.tryParse(source);
  }

  bool _isExcluded(html_dom.Element element) =>
      _isExcludedWithoutStyle(element) ||
      _isExcludedByStyle(element, _elementStyle(element));

  bool _isExcludedWithoutStyle(html_dom.Element element) =>
      _excludedTags.contains(element.localName?.toLowerCase()) ||
      element.classes.contains('blockcode') ||
      element.classes.contains('showcollapse_gather') ||
      element.attributes.containsKey('hidden');

  bool _isExcludedByStyle(
    html_dom.Element element,
    CssInlineStyleDeclarationList? style,
  ) {
    final display = style
        ?.effectiveDeclaration({'display'})
        ?.value
        .toLowerCase();
    final visibility = style
        ?.effectiveDeclaration({'visibility'})
        ?.value
        .toLowerCase();
    final opacity = style?.effectiveDeclaration({'opacity'})?.value;
    final contentVisibility = style
        ?.effectiveDeclaration({'content-visibility'})
        ?.value
        .toLowerCase();
    return (display == 'none' && !_isManagedCollapseContent(element)) ||
        visibility == 'hidden' ||
        visibility == 'collapse' ||
        contentVisibility == 'hidden' ||
        double.tryParse(opacity ?? '') == 0;
  }

  bool _isManagedCollapseContent(html_dom.Element element) {
    if (!element.classes.contains('showcollapse_content')) return false;
    final parent = element.parentNode;
    if (parent is! html_dom.Element ||
        !parent.classes.contains('showcollapse_box')) {
      return false;
    }
    for (final child in parent.children) {
      if (child.classes.contains('showcollapse_content')) {
        // The renderer extracts only this direct child's innerHtml, replacing
        // Discuz's display:none with the native fold's expansion lifecycle.
        return identical(child, element);
      }
    }
    return false;
  }

  String? _leadingVisibleText(Iterable<html_dom.Node> candidates) {
    // A small look-ahead only rejects obvious URL continuations across hard
    // breaks; it neither flattens the document nor rescans later paragraphs.
    final pending = candidates.take(32).toList().reversed.toList();
    for (var inspected = 0; pending.isNotEmpty && inspected < 32; inspected++) {
      final node = pending.removeLast();
      if (node is html_dom.Text && node.data.trim().isNotEmpty) {
        return node.data.length <= 256
            ? node.data
            : node.data.substring(0, 256);
      }
      if (node is html_dom.Element) {
        if (_isExcluded(node)) return null;
        pending.addAll(node.nodes.take(32).toList().reversed);
      }
    }
    return null;
  }

  void _replaceText(
    html_dom.Text node,
    List<ForumHttpTextLink> links,
    String color,
  ) {
    final parent = node.parentNode;
    if (parent == null) return;
    final source = node.data;
    var offset = 0;
    for (final link in links) {
      if (link.start > offset) {
        parent.insertBefore(
          html_dom.Text(source.substring(offset, link.start)),
          node,
        );
      }
      final anchor = html_dom.Element.tag('a')
        ..attributes['href'] = link.text
        ..attributes['style'] = 'color: $color'
        ..append(html_dom.Text(link.text));
      parent.insertBefore(anchor, node);
      offset = link.end;
    }
    if (offset < source.length) {
      parent.insertBefore(html_dom.Text(source.substring(offset)), node);
    }
    node.remove();
  }

  String _cssColor(ForumHtmlThemeContext theme) =>
      '#${(theme.link.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}
