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

  static const _codec = HtmlPackageForumHtmlFragmentCodec();
  static final _rootWhitespace = RegExp(r'^[\t\n\f\r ]*$');
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

  ForumHtmlSafeDisplayPlan plan(ForumHtmlPreparedRenderDocument document) {
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
    final fragment = _codec.parse(html);
    final nodes = fragment.nodes.toList(growable: false);
    final onlyLines = nodes.every(
      (node) => node is dom.Text || node is dom.Comment || _isBareBreak(node),
    );
    final List<_DisplayPart> parts;
    final ForumHtmlSafeDisplayPlanKind kind;
    if (onlyLines) {
      parts = _textLines(nodes);
      kind = ForumHtmlSafeDisplayPlanKind.textLines;
    } else if (_areParagraphRoots(nodes)) {
      parts = _paragraphs(nodes);
      kind = ForumHtmlSafeDisplayPlanKind.paragraphs;
    } else {
      return _whole(
        document,
        ForumHtmlSafeDisplayFallbackReason.unsupportedStructure,
      );
    }
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
      if (child.localName == 'a') {
        final uri = Uri.tryParse(child.attributes['href'] ?? '');
        if (uri == null ||
            (uri.scheme != 'http' && uri.scheme != 'https') ||
            uri.host.isEmpty) {
          return false;
        }
      }
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
      (node) => node is dom.Text && node.data.trim().isNotEmpty,
    );
    final groups = <({List<dom.Node> nodes, int startUnit, int endUnit})>[];
    var pending = <dom.Node>[];
    var cost = 0;
    var unit = 0;
    var startUnit = 0;
    var hasLineText = false;
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      if (_isBareBreak(node) &&
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
        if (node is dom.Text) {
          cost += node.data.length;
          hasLineText = hasLineText || node.data.trim().isNotEmpty;
        }
      }
      if (_isBareBreak(node)) {
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

  static String _serialize(List<dom.Node> nodes) {
    final fragment = dom.DocumentFragment()..nodes.addAll(nodes);
    return _codec.serialize(fragment);
  }
}

typedef _DisplayPart = ({String html, int startUnit, int endUnit});
