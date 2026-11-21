import 'package:flutter/foundation.dart' show internal;
import 'package:html/dom.dart' as dom;

import '../models/forum_html_safe_display_plan.dart';
import 'forum_html_fragment_codec.dart';
import 'forum_html_prepared_render_document.dart';
import 'theme/css_inline_style_declarations.dart';

/// Admits independent display blocks only; it does not slice text coordinates.
/// Call in data preparation before mounting a long body, not inside its build.
final class ForumHtmlSafeDisplayPlanner {
  const ForumHtmlSafeDisplayPlanner({
    this.minCodeUnits = 32 * 1024,
    this.targetChunkCodeUnits = 1600,
    this.maxChunkCodeUnits = 8192,
    this.targetChunkUnits,
    this.fragmentCodec = const HtmlPackageForumHtmlFragmentCodec(),
  }) : assert(minCodeUnits >= 0),
       assert(targetChunkCodeUnits > 0),
       assert(maxChunkCodeUnits >= targetChunkCodeUnits),
       assert(targetChunkUnits == null || targetChunkUnits > 0);

  final int minCodeUnits;
  final int targetChunkCodeUnits;
  final int maxChunkCodeUnits;

  /// Groups by hard lines/P blocks instead of text length when specified.
  /// Blank hard lines stay with neighboring text so fwfh keeps their geometry.
  final int? targetChunkUnits;

  /// Returns a fragment owned by this planning call; no DOM enters the plan.
  final ForumHtmlFragmentCodec fragmentCodec;

  static final _rootWhitespace = RegExp(r'^[\t\n\f\r ]*$');
  static final _unsupportedLeadingRoot = RegExp(
    r'^[\t\n\f\r ]*<(?:div[\t\n\f\r ]+[a-z_:]|span(?=[\t\n\f\r />]))',
    caseSensitive: false,
  );
  static const _inlineTags = {
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
    'sub',
    'sup',
    'br',
    'a',
  };
  static const _textProperties = {
    'color',
    'font-size',
    'font-family',
    'font-weight',
    'font-style',
    'line-height',
    'letter-spacing',
    'word-spacing',
    'text-align',
    'text-decoration',
    'text-decoration-color',
    'text-decoration-line',
    'text-decoration-style',
    'text-indent',
    'direction',
  };
  static const _lineLinkAttributes = {
    'href',
    'title',
    'target',
    'rel',
    'style',
  };

  ForumHtmlSafeDisplayPlan plan(ForumHtmlPreparedRenderDocument document) =>
      planPrepared(document);

  /// [ownedFragment] is the canonical fragment just serialized by preparation.
  /// Planning can detach its roots after the complete HTML has been saved.
  @internal
  ForumHtmlSafeDisplayPlan planPrepared(
    ForumHtmlPreparedRenderDocument document, {
    dom.DocumentFragment? ownedFragment,
  }) {
    final html = document.preparedHtml;
    if (html.length < minCodeUnits) {
      return _whole(
        document,
        ForumHtmlSafeDisplayFallbackReason.belowThreshold,
      );
    }
    if (!html.contains('<')) {
      return _whole(
        document,
        ForumHtmlSafeDisplayFallbackReason.noSafeBoundaries,
      );
    }
    // The canonical parser cannot admit these leading roots. Bound the prefix
    // check; custom codecs and uncertain prefixes keep their full DOM check.
    if (fragmentCodec is HtmlPackageForumHtmlFragmentCodec &&
        _unsupportedLeadingRoot.hasMatch(
          html.length <= 512 ? html : html.substring(0, 512),
        )) {
      return _whole(
        document,
        ForumHtmlSafeDisplayFallbackReason.unsupportedStructure,
      );
    }
    // A character reference can introduce a literal CR after tokenization.
    // Reparsing serialized HTML normalizes CR/CRLF, including in attributes.
    final fragment =
        ownedFragment != null &&
            fragmentCodec is HtmlPackageForumHtmlFragmentCodec &&
            !html.contains('\r')
        ? ownedFragment
        : fragmentCodec.parse(html);
    final wrapper = _soleBareDiv(fragment);
    final parent = wrapper ?? fragment;
    final nodes = parent.nodes.toList(growable: false);
    final ForumHtmlSafeDisplayPlanKind kind;
    if (_areTextLineRoots(nodes)) {
      kind = ForumHtmlSafeDisplayPlanKind.textLines;
    } else if ((wrapper == null || _hasPlainParagraphChildren(wrapper)) &&
        _areParagraphRoots(nodes)) {
      kind = ForumHtmlSafeDisplayPlanKind.paragraphs;
    } else {
      return _whole(
        document,
        ForumHtmlSafeDisplayFallbackReason.unsupportedStructure,
      );
    }
    // html's addAll reparents with List.remove. Removing successive groups from
    // a long sibling list is quadratic even in reverse group order. Detach the
    // owned roots together, leaving each complete root's children untouched.
    parent.nodes.clear();
    final parts = kind == ForumHtmlSafeDisplayPlanKind.textLines
        ? _textLines(nodes)
        : _paragraphs(nodes);
    if (parts.length < 2) {
      return _whole(
        document,
        ForumHtmlSafeDisplayFallbackReason.noSafeBoundaries,
      );
    }
    if (parts.any((part) => part.html.length > maxChunkCodeUnits)) {
      return _whole(
        document,
        ForumHtmlSafeDisplayFallbackReason.oversizedChunk,
      );
    }
    return ForumHtmlSafeDisplayPlan(
      sourceHtml: html,
      sourceId: document.sequence.sourceId,
      kind: kind,
      chunks: [
        for (var index = 0; index < parts.length; index++)
          _chunk(document, index, parts[index], index + 1 < parts.length),
      ],
    );
  }

  ForumHtmlSafeDisplayPlan _whole(
    ForumHtmlPreparedRenderDocument document,
    ForumHtmlSafeDisplayFallbackReason reason,
  ) => ForumHtmlSafeDisplayPlan(
    sourceHtml: document.preparedHtml,
    sourceId: document.sequence.sourceId,
    kind: ForumHtmlSafeDisplayPlanKind.whole,
    fallbackReason: reason,
    chunks: [
      _chunk(document, 0, (
        html: document.preparedHtml,
        startUnit: 0,
        endUnit: 1,
      ), false),
    ],
  );

  ForumHtmlDisplayChunk _chunk(
    ForumHtmlPreparedRenderDocument document,
    int ordinal,
    _DisplayPart part,
    bool hasTrailingContent,
  ) => ForumHtmlDisplayChunk(
    ordinal: ordinal,
    html: part.html,
    hasTrailingContent: hasTrailingContent,
    sourceId: document.sequence.sourceId,
    sourceHtml: document.preparedHtml,
    startUnit: part.startUnit,
    endUnit: part.endUnit,
  );

  static bool _isBareBreak(dom.Node node) =>
      node is dom.Element && node.localName == 'br' && node.attributes.isEmpty;

  static bool _areTextLineRoots(List<dom.Node> nodes) {
    late final declarations = CssInlineStyleDeclarationCodec.scoped();
    // Only direct BRs are boundaries. An inline subtree must fit on one hard
    // line, so a cut never splits a recognizer or reopens a formatting tag.
    final pending = <dom.Node>[];
    for (final root in nodes) {
      if (root is dom.Text || root is dom.Comment || _isBareBreak(root)) {
        continue;
      }
      pending.add(root);
      while (pending.isNotEmpty) {
        final node = pending.removeLast();
        if (node is dom.Text || node is dom.Comment) continue;
        if (node is! dom.Element) return false;
        switch (node.localName) {
          case 'a':
            if (!_isWebLink(node) ||
                !node.attributes.keys.every(_lineLinkAttributes.contains)) {
              return false;
            }
          case 'b':
          case 'strong':
            if (node.attributes.keys.any((key) => key != 'style')) return false;
          case 'font':
            // Theme adaptation can move color into style or remove it entirely.
            if (node.attributes.keys.any(
              (key) => key != 'color' && key != 'style',
            )) {
              return false;
            }
          default:
            return false;
        }
        // Color alone does not change line metrics.
        final style = node.attributes['style'];
        if (style != null && style.isNotEmpty) {
          final parsed = declarations.tryParse(style);
          if (parsed == null ||
              parsed.declarations.any((item) => item.property != 'color')) {
            return false;
          }
        }
        pending.addAll(node.nodes);
      }
    }
    return true;
  }

  static bool _isWebLink(dom.Element element) {
    final uri = Uri.tryParse(element.attributes['href'] ?? '');
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static dom.Element? _soleBareDiv(dom.DocumentFragment fragment) {
    final first = fragment.nodes.whereType<dom.Element>().firstOrNull;
    if (first == null ||
        first.localName != 'div' ||
        first.attributes.isNotEmpty) {
      return null;
    }
    return fragment.nodes.every(
          (node) =>
              identical(node, first) ||
              node is dom.Comment ||
              node is dom.Text && _rootWhitespace.hasMatch(node.data),
        )
        ? first
        : null;
  }

  // A DIV can have its own paragraph margin in the host. Only flatten P
  // children whose default margins match, even if their inline text is styled.
  static bool _hasPlainParagraphChildren(dom.Element wrapper) =>
      wrapper.children.length >= 2 &&
      wrapper.children.every((p) => p.localName == 'p' && p.attributes.isEmpty);

  static bool _areParagraphRoots(List<dom.Node> nodes) {
    final declarations = CssInlineStyleDeclarationCodec.scoped();
    return nodes.every((node) => _isParagraphRoot(node, declarations));
  }

  static bool _isParagraphRoot(
    dom.Node node,
    CssInlineStyleDeclarationCodec declarations,
  ) {
    if (node is dom.Comment ||
        node is dom.Text && _rootWhitespace.hasMatch(node.data)) {
      return true;
    }
    if (node is! dom.Element ||
        node.localName != 'p' ||
        !_hasTextAttributes(node, declarations)) {
      return false;
    }
    final pending = <dom.Node>[...node.nodes];
    var hasText = false;
    while (pending.isNotEmpty) {
      final child = pending.removeLast();
      if (child is dom.Text) {
        hasText = hasText || child.data.trim().isNotEmpty;
        continue;
      }
      if (child is dom.Comment) continue;
      if (child is! dom.Element ||
          !_inlineTags.contains(child.localName) ||
          !_hasTextAttributes(child, declarations)) {
        return false;
      }
      if (child.localName == 'a' && !_isWebLink(child)) return false;
      pending.addAll(child.nodes);
    }
    // Empty blocks have margin-collapse behavior across neighboring P roots.
    return hasText;
  }

  static bool _hasTextAttributes(
    dom.Element element,
    CssInlineStyleDeclarationCodec declarations,
  ) {
    for (final attribute in element.attributes.keys) {
      if (!{
        'style',
        'color',
        'size',
        'face',
        'align',
        'dir',
        'lang',
        'title',
        'href',
      }.contains(attribute)) {
        return false;
      }
    }
    final style = element.attributes['style'];
    if (style == null || style.isEmpty) return true;
    final parsed = declarations.tryParse(style);
    if (parsed == null) return false;
    return parsed.declarations.every(
      (declaration) =>
          _textProperties.contains(declaration.property) ||
          declaration.property == 'margin' &&
              {'0', '0px'}.contains(declaration.value.trim()),
    );
  }

  List<_DisplayPart> _textLines(List<dom.Node> nodes) {
    final lastText = nodes.lastIndexWhere(
      (node) => _lineText(node).trim().isNotEmpty,
    );
    final groups = <({List<dom.Node> nodes, int startUnit, int endUnit})>[];
    var pending = <dom.Node>[];
    var cost = 0;
    var unit = 0;
    var startUnit = 0;
    var hasLineText = false;
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final isBreak = _isBareBreak(node);
      if (isBreak &&
          hasLineText &&
          (targetChunkUnits != null
              ? unit + 1 - startUnit >= targetChunkUnits!
              : cost >= targetChunkCodeUnits) &&
          index < lastText) {
        // A block boundary replaces this exact one line break. Consecutive and
        // trailing breaks remain with the final text: a standalone BR-only
        // fwfh block has different line-height and must never become the tail.
        groups.add((nodes: pending, startUnit: startUnit, endUnit: unit + 1));
        pending = <dom.Node>[];
        cost = 0;
        startUnit = unit + 1;
      } else {
        pending.add(node);
        if (!isBreak) {
          final text = _lineText(node);
          cost += text.length;
          hasLineText = hasLineText || text.trim().isNotEmpty;
        }
      }
      if (isBreak) {
        unit++;
        hasLineText = false;
      }
    }
    groups.add((nodes: pending, startUnit: startUnit, endUnit: unit + 1));
    if (groups.length < 2) return const [];
    return [
      for (final group in groups)
        (
          html: _serialize([
            dom.Element.tag('y300-forum-text-chunk')
              ..attributes['style'] = 'display:block;margin:0'
              ..nodes.addAll(group.nodes),
          ]),
          startUnit: group.startUnit,
          endUnit: group.endUnit,
        ),
    ];
  }

  static String _lineText(dom.Node node) => switch (node) {
    dom.Text() => node.data,
    dom.Element() => node.text,
    _ => '',
  };

  List<_DisplayPart> _paragraphs(List<dom.Node> nodes) {
    final parts = <_DisplayPart>[];
    final pending = StringBuffer();
    var unit = 0;
    var startUnit = 0;
    for (final node in nodes) {
      // Serialize each complete root once; the same bytes supply its budget and
      // final chunk. Inline DOM need not be walked again just to measure length.
      pending.write(_serialize([node]));
      if (node is dom.Element) unit++;
      if (node is dom.Element &&
          (targetChunkUnits != null
              ? unit - startUnit >= targetChunkUnits!
              : pending.length >= targetChunkCodeUnits)) {
        parts.add((
          html: pending.toString(),
          startUnit: startUnit,
          endUnit: unit,
        ));
        pending.clear();
        startUnit = unit;
      }
    }
    if (pending.isNotEmpty) {
      if (parts.isEmpty || targetChunkUnits != null && unit > startUnit) {
        parts.add((
          html: pending.toString(),
          startUnit: startUnit,
          endUnit: unit,
        ));
      } else {
        final previous = parts.last;
        parts[parts.length - 1] = (
          html: previous.html + pending.toString(),
          startUnit: previous.startUnit,
          endUnit: unit,
        );
      }
    }
    return parts;
  }

  String _serialize(List<dom.Node> nodes) {
    final fragment = dom.DocumentFragment()..nodes.addAll(nodes);
    return fragmentCodec.serialize(fragment);
  }
}

typedef _DisplayPart = ({String html, int startUnit, int endUnit});
