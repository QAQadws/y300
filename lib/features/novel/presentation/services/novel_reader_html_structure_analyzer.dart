import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/presentation/models/novel_reader_html_structure_report.dart';

/// Produces a privacy-safe structural report for a captured forum HTML page.
///
/// This is a Phase 0 investigation tool. It is intentionally independent from
/// the renderer and does not mutate the source DOM or prepare a second copy of
/// chapter content. The selector order mirrors the existing forum fragment
/// extraction boundary so the report describes the same first message that the
/// renderer would receive.
final class NovelReaderHtmlStructureAnalyzer {
  const NovelReaderHtmlStructureAnalyzer();

  static const List<String> _messageSelectors = <String>[
    '[id^="postmessage_"]',
    'td.t_f',
    '.message',
    '.t_f',
    '.pcb',
    'article',
    'body',
  ];

  NovelReaderHtmlStructureReport analyze({
    required String fixtureId,
    required String rawHtml,
  }) {
    final document = html_parser.parse(rawHtml);
    final message = _selectMessage(document);
    final messageRoot = message?.$1;
    final messageHtml = messageRoot?.innerHtml ?? '';
    final messageText = messageRoot == null
        ? ''
        : _ordinaryTextContent(messageRoot);
    final sensitiveMarkers = messageRoot == null
        ? const <String>[]
        : _sensitiveMarkers(messageHtml);

    return NovelReaderHtmlStructureReport(
      fixtureId: fixtureId,
      sourceUtf8Bytes: utf8.encode(rawHtml).length,
      messageFound: messageRoot != null,
      messageSelector: message?.$2 ?? '',
      messageUtf8Bytes: utf8.encode(messageHtml).length,
      messageTextRunes: messageText.runes.length,
      ordinaryTextNodeCount: messageRoot == null
          ? 0
          : _ordinaryTextNodes(messageRoot),
      ordinaryTextRuneCount: messageRoot == null
          ? 0
          : _ordinaryTextRunes(messageRoot),
      fontTagCount: messageRoot == null
          ? 0
          : _countElements(
              messageRoot,
              (element) => element.localName == 'font',
            ),
      fontSizeDeclarationCount: messageRoot == null
          ? 0
          : _countStyleDeclarations(messageRoot, _fontSizePattern),
      foregroundColorDeclarationCount: messageRoot == null
          ? 0
          : _countForegroundDeclarations(messageRoot),
      backgroundColorDeclarationCount: messageRoot == null
          ? 0
          : _countStyleDeclarations(messageRoot, _backgroundPattern),
      imageCount: messageRoot == null
          ? 0
          : _countElements(
              messageRoot,
              (element) => element.localName == 'img',
            ),
      collapseBlockCount: messageRoot == null
          ? 0
          : _countClass(messageRoot, 'showcollapse_box'),
      expandedCollapseBlockCount: messageRoot == null
          ? 0
          : _countElements(
              messageRoot,
              (element) =>
                  element.classes.contains('showcollapse_box') &&
                  element.classes.contains('showcollapse_active'),
            ),
      tableCount: messageRoot == null
          ? 0
          : _countElements(
              messageRoot,
              (element) => element.localName == 'table',
            ),
      tableRowCount: messageRoot == null
          ? 0
          : _countElements(messageRoot, (element) => element.localName == 'tr'),
      tableCellCount: messageRoot == null
          ? 0
          : _countElements(
              messageRoot,
              (element) =>
                  element.localName == 'td' || element.localName == 'th',
            ),
      rubyCount: messageRoot == null
          ? 0
          : _countElements(
              messageRoot,
              (element) => element.localName == 'ruby',
            ),
      rubyAnnotationCount: messageRoot == null
          ? 0
          : _countElements(messageRoot, (element) => element.localName == 'rt'),
      rubyFallbackCount: messageRoot == null
          ? 0
          : _countElements(messageRoot, (element) => element.localName == 'rp'),
      scriptCount: document.querySelectorAll('script').length,
      messageSensitiveMarkers: sensitiveMarkers,
    );
  }

  (html_dom.Element, String)? _selectMessage(html_dom.Document document) {
    for (final selector in _messageSelectors) {
      final element = document.querySelector(selector);
      if (element != null) {
        return (element, selector);
      }
    }
    return null;
  }

  int _ordinaryTextNodes(html_dom.Element root) {
    var count = 0;
    _walk(root, (node, blocked) {
      if (!blocked && node is html_dom.Text && node.data.trim().isNotEmpty) {
        count += 1;
      }
    });
    return count;
  }

  int _ordinaryTextRunes(html_dom.Element root) {
    var count = 0;
    _walk(root, (node, blocked) {
      if (!blocked && node is html_dom.Text && node.data.trim().isNotEmpty) {
        count += node.data.runes.length;
      }
    });
    return count;
  }

  String _ordinaryTextContent(html_dom.Element root) {
    final buffer = StringBuffer();
    _walk(root, (node, blocked) {
      if (!blocked && node is html_dom.Text) {
        buffer.write(node.data);
      }
    });
    return buffer.toString();
  }

  void _walk(
    html_dom.Node node,
    void Function(html_dom.Node node, bool blocked) visitor, {
    bool blocked = false,
  }) {
    final nextBlocked =
        blocked ||
        (node is html_dom.Element &&
            const <String>{
              'script',
              'style',
              'noscript',
            }.contains(node.localName));
    visitor(node, nextBlocked);
    for (final child in node.nodes) {
      _walk(child, visitor, blocked: nextBlocked);
    }
  }

  int _countElements(
    html_dom.Element root,
    bool Function(html_dom.Element element) predicate,
  ) {
    var count = predicate(root) ? 1 : 0;
    for (final element in root.querySelectorAll('*')) {
      if (predicate(element)) {
        count += 1;
      }
    }
    return count;
  }

  int _countClass(html_dom.Element root, String className) {
    return _countElements(
      root,
      (element) => element.classes.contains(className),
    );
  }

  int _countStyleDeclarations(
    html_dom.Element root,
    RegExp declarationPattern,
  ) {
    return _countElements(
      root,
      (element) =>
          declarationPattern.hasMatch(element.attributes['style'] ?? ''),
    );
  }

  int _countForegroundDeclarations(html_dom.Element root) {
    return _countElements(
      root,
      (element) =>
          element.attributes.containsKey('color') ||
          _foregroundPattern.hasMatch(element.attributes['style'] ?? ''),
    );
  }

  List<String> _sensitiveMarkers(String messageHtml) {
    final lower = messageHtml.toLowerCase();
    final markers = <String>[];
    if (lower.contains('document.cookie') ||
        lower.contains('cookie:') ||
        lower.contains('set-cookie')) {
      markers.add('cookie');
    }
    if (lower.contains('authorization:') || lower.contains('bearer ')) {
      markers.add('authorization');
    }
    if (lower.contains('"auth"') || lower.contains("'auth'")) {
      markers.add('auth-field');
    }
    return List<String>.unmodifiable(markers);
  }
}

final RegExp _fontSizePattern = RegExp(
  r'(^|;)\s*font-size\s*:',
  caseSensitive: false,
);
final RegExp _foregroundPattern = RegExp(
  r'(^|;)\s*(color|text-decoration-color)\s*:',
  caseSensitive: false,
);
final RegExp _backgroundPattern = RegExp(
  r'(^|;)\s*background(?:-color)?\s*:',
  caseSensitive: false,
);
