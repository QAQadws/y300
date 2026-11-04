import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../html_rendering/theme/css_inline_style_declarations.dart';
import 'forum_body_document.dart';
import 'forum_body_discuz_code_chrome.dart';

final class ForumBodyParseLimits {
  const ForumBodyParseLimits({
    this.maxCodeUnits = 2 * 1024 * 1024,
    this.maxNodes = 100000,
    this.maxDepth = 96,
  }) : assert(maxCodeUnits >= 0),
       assert(maxNodes >= 0),
       assert(maxDepth > 0);
  final int maxCodeUnits;
  final int maxNodes;
  final int maxDepth;
}

enum ForumBodyParseFailure { inputLimit, nodeLimit, depthLimit }

/// Machine-readable failure; never contains server payload or UI copy.
final class ForumBodyParseException implements Exception {
  const ForumBodyParseException(this.failure);
  final ForumBodyParseFailure failure;
  @override
  String toString() => 'ForumBodyParseException(${failure.name})';
}

final class ForumBodyParser {
  const ForumBodyParser({
    this.fragmentParser = const DefaultHtmlFragmentParser(),
    this.limits = const ForumBodyParseLimits(),
  });
  static const revision = 3;
  final HtmlFragmentParser fragmentParser;
  final ForumBodyParseLimits limits;

  ForumBodyDocument parse({
    required String html,
    required String sourceId,
    required String conversionIdentity,
  }) {
    if (html.length > limits.maxCodeUnits) {
      throw const ForumBodyParseException(ForumBodyParseFailure.inputLimit);
    }
    final fragment = fragmentParser.parse(html);
    final count = _validate(fragment);
    final source = HtmlSourceTextMap.parse(
      html,
      fragmentParser: _ParsedFragment(fragment),
      protectedInlinePredicate: _isProtectedInline,
    );
    final builder = _BodyBuilder(source);
    return ForumBodyDocument(
      identity: ForumBodyIdentity(
        sourceId: sourceId,
        inputHash: sha256.convert(utf8.encode(html)).toString(),
        conversionIdentity: conversionIdentity,
        parserRevision: revision,
      ),
      sourceMap: source,
      nodes: builder.children(fragment.nodes, ''),
      issues: builder.issues,
      parsedNodeCount: count,
      uniqueStyleCount: builder.styles.length,
    );
  }

  int _validate(dom.DocumentFragment fragment) {
    var count = 0;
    final pending = <({Iterator<dom.Node> nodes, int depth})>[
      (nodes: fragment.nodes.iterator, depth: 1),
    ];
    while (pending.isNotEmpty) {
      final frame = pending.last;
      if (!frame.nodes.moveNext()) {
        pending.removeLast();
        continue;
      }
      if (++count > limits.maxNodes) {
        throw const ForumBodyParseException(ForumBodyParseFailure.nodeLimit);
      }
      if (frame.depth > limits.maxDepth) {
        throw const ForumBodyParseException(ForumBodyParseFailure.depthLimit);
      }
      final node = frame.nodes.current;
      if (node.nodes.isNotEmpty && !_isActive(node)) {
        pending.add((nodes: node.nodes.iterator, depth: frame.depth + 1));
      }
    }
    return count;
  }
}

final class _ParsedFragment implements HtmlFragmentParser {
  const _ParsedFragment(this.fragment);
  final dom.DocumentFragment fragment;
  @override
  dom.DocumentFragment parse(String _) => fragment;
}

bool _isActive(dom.Node node) =>
    node is dom.Element && const {'script', 'style'}.contains(node.localName);

bool _isProtectedInline(dom.Element element) => const {
  'img',
  'iframe',
  'object',
  'video',
  'audio',
}.contains(element.localName);

final class _BodyBuilder {
  _BodyBuilder(this.source);
  final HtmlSourceTextMap source;
  final issues = <ForumBodyIssue>[];
  final styles = <String, ForumBodyAuthorStyle>{};
  final codec = CssInlineStyleDeclarationCodec.scoped();

  List<ForumBodyNode> children(List<dom.Node> nodes, String prefix) {
    final result = <ForumBodyNode>[];
    dom.Element? preceding;
    for (var i = 0; i < nodes.length; i++) {
      final raw = nodes[i];
      final value = node(raw, prefix.isEmpty ? '$i' : '$prefix/$i', preceding);
      if (value != null) result.add(value);
      if (raw is dom.Element) {
        preceding = raw;
      } else if (raw is dom.Text && raw.data.trim().isNotEmpty) {
        preceding = null;
      }
    }
    return result;
  }

  ForumBodyNode? node(dom.Node node, String path, dom.Element? preceding) {
    if (_isActive(node)) {
      issues.add(ForumBodyIssue(ForumBodyIssueCode.removedActiveContent, path));
      return null;
    }
    if (node is dom.Text) {
      return ForumBodyText(
        path: path,
        source: source.rangesByPath[path]!,
        text: node.data,
      );
    }
    if (node is! dom.Element) return null;
    final tag = node.localName ?? '';
    final rawStyle = node.attributes['style'] ?? '';
    final style = styles.putIfAbsent(rawStyle, () {
      final parsed = codec.tryParse(rawStyle);
      return ForumBodyAuthorStyle(
        isValid: parsed != null,
        declarations: [
          for (final declaration
              in parsed?.declarations ?? const <CssInlineStyleDeclaration>[])
            ForumBodyDeclaration(
              declaration.property,
              declaration.value,
              declaration.important,
            ),
        ],
      );
    });
    if (!style.isValid) {
      issues.add(ForumBodyIssue(ForumBodyIssueCode.invalidStyle, path));
    }
    final attributes = <String, String>{};
    for (final entry in node.attributes.entries) {
      final name = entry.key.toString();
      if (name.toLowerCase().startsWith('on')) {
        issues.add(
          ForumBodyIssue(ForumBodyIssueCode.removedEventAttribute, path),
        );
      } else {
        attributes[name] = entry.value;
      }
    }
    final kind = _kind(node, preceding);
    if (kind == ForumBodyElementKind.unknown) {
      issues.add(ForumBodyIssue(ForumBodyIssueCode.unknownElement, path));
    }
    return ForumBodyElement(
      path: path,
      source: source.rangesByPath[path]!,
      tag: tag,
      kind: kind,
      attributes: attributes,
      style: style,
      children: children(node.nodes, path),
      resource:
          kind == ForumBodyElementKind.image ||
              kind == ForumBodyElementKind.media
          ? _resource(node, attributes)
          : null,
    );
  }

  ForumBodyResourceReference _resource(
    dom.Element element,
    Map<String, String> attributes,
  ) => ForumBodyResourceReference(
    rawSource: DefaultForumImageSourcePipeline.firstDomImageSourceFromElement(
      element,
      domAttributes: const [
        'zoomfile',
        'file',
        'data-original',
        'data-src',
        'src',
        'data',
      ],
    ),
    readableImageIndex: int.tryParse(
      attributes['data-y300-readable-image-index'] ?? '',
    ),
    attachmentId: attributes['aid'],
    alt: attributes['alt'],
    title: attributes['title'],
    width: _dimension(attributes['width']),
    height: _dimension(attributes['height']),
  );

  double? _dimension(String? value) {
    final number = double.tryParse(value ?? '');
    return number != null && number.isFinite && number > 0 ? number : null;
  }

  ForumBodyElementKind _kind(dom.Element node, dom.Element? preceding) {
    if (forumBodyIsDiscuzCodeCopyControl(node, preceding)) {
      // Preserve its real source/path; hidden chrome owns no visible text.
      return ForumBodyElementKind.hidden;
    }
    final classes = node.classes;
    for (final entry in const {
      'showcollapse_box': ForumBodyElementKind.collapse,
      'showcollapse_title': ForumBodyElementKind.collapseTitle,
      'showcollapse_content': ForumBodyElementKind.collapseContent,
      'pstatus': ForumBodyElementKind.editStatus,
      'blockcode': ForumBodyElementKind.code,
      'quote': ForumBodyElementKind.quote,
      'locked': ForumBodyElementKind.locked,
      'locked-content': ForumBodyElementKind.locked,
      'tattl': ForumBodyElementKind.attachment,
    }.entries) {
      if (classes.contains(entry.key)) return entry.value;
    }
    return switch (node.localName) {
      'p' => ForumBodyElementKind.paragraph,
      'template' => ForumBodyElementKind.hidden,
      'div' ||
      'section' ||
      'article' ||
      'figure' ||
      'figcaption' ||
      'dl' ||
      'dd' ||
      'dt' ||
      'ignore_js_op' => ForumBodyElementKind.container,
      'h1' ||
      'h2' ||
      'h3' ||
      'h4' ||
      'h5' ||
      'h6' => ForumBodyElementKind.heading,
      'blockquote' => ForumBodyElementKind.quote,
      'ul' || 'ol' => ForumBodyElementKind.list,
      'li' => ForumBodyElementKind.listItem,
      'pre' || 'code' => ForumBodyElementKind.code,
      'br' => ForumBodyElementKind.hardBreak,
      'hr' => ForumBodyElementKind.rule,
      'img' => ForumBodyElementKind.image,
      'ruby' => ForumBodyElementKind.ruby,
      'rb' => ForumBodyElementKind.rubyBase,
      'rt' => ForumBodyElementKind.rubyText,
      'rtc' => ForumBodyElementKind.rubyAnnotationContainer,
      'rp' => ForumBodyElementKind.rubyFallback,
      'table' => ForumBodyElementKind.table,
      'thead' || 'tbody' || 'tfoot' => ForumBodyElementKind.tableSection,
      'tr' => ForumBodyElementKind.tableRow,
      'td' || 'th' => ForumBodyElementKind.tableCell,
      'iframe' ||
      'video' ||
      'audio' ||
      'object' ||
      'embed' => ForumBodyElementKind.media,
      'span' ||
      'font' ||
      'a' ||
      'b' ||
      'strong' ||
      'i' ||
      'em' ||
      'u' ||
      's' ||
      'strike' ||
      'del' ||
      'small' ||
      'mark' ||
      'sub' ||
      'sup' ||
      'label' ||
      'q' ||
      'abbr' => ForumBodyElementKind.inline,
      _ => ForumBodyElementKind.unknown,
    };
  }
}
