import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/reader_shared/domain/rich_text/typography/discuz_font_size_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';

class ForumHtmlStylePolicy {
  const ForumHtmlStylePolicy(this.preferences);

  final ForumHtmlReaderPreferences preferences;

  TextStyle baseTextStyle(BuildContext context) {
    final fallback = Theme.of(context).textTheme.bodyMedium;
    final baseFontSize = fallback?.fontSize ?? 14;
    return (fallback ?? const TextStyle()).copyWith(
      fontSize: baseFontSize * preferences.typography.fontScale,
      height: preferences.typography.lineHeightScale,
    );
  }

  StylesMap? customStylesFor(html_dom.Element element) {
    if (isForumCollapseElement(element) ||
        isForumCollapseGatherElement(element)) {
      return {'display': 'none'};
    }
    if (_isCodeLike(element)) {
      return {
        'font-family': 'monospace',
        'white-space': 'pre-wrap',
        'overflow-wrap': 'anywhere',
      };
    }
    if (_isTable(element)) {
      return {
        'border-collapse': 'collapse',
        'border-spacing': '0',
        'margin': '0 0 ${preferences.typography.paragraphSpacing}px',
        'max-width': '100%',
      };
    }
    if (_isTableCell(element)) {
      return {
        'border': '1px solid #d0d0d0',
        'padding': '4px 6px',
        'vertical-align': 'top',
      };
    }
    if (_isContentImage(element)) {
      return {'display': 'block', 'max-width': '100%'};
    }
    if (_isContentImageOnlyAnchor(element)) {
      return {'display': 'block'};
    }
    if (_isParagraphLike(element)) {
      return {'margin': '0 0 ${preferences.typography.paragraphSpacing}px'};
    }
    return null;
  }

  bool isDiscuzEditStatusElement(html_dom.Element element) {
    return element.classes.contains('pstatus');
  }

  bool isForumCollapseElement(html_dom.Element element) {
    return element.classes.contains('showcollapse_box');
  }

  bool isForumCollapseGatherElement(html_dom.Element element) {
    return element.classes.contains('showcollapse_gather');
  }

  bool isForumCollapseInitiallyExpanded(html_dom.Element element) {
    return element.classes.contains('showcollapse_active');
  }

  String prepareHtml(String html) {
    final fragment = html_parser.parseFragment(html);
    for (final element in fragment.querySelectorAll('[style],font')) {
      _sanitizeStyle(element);
      _sanitizeFontElement(element);
    }
    return fragment.nodes.map(_serializeNode).join();
  }

  bool _isParagraphLike(html_dom.Element element) {
    final tagName = element.localName?.toLowerCase();
    return tagName == 'p' || tagName == 'div' || tagName == 'blockquote';
  }

  bool _isCodeLike(html_dom.Element element) {
    final tagName = element.localName?.toLowerCase();
    return tagName == 'pre' ||
        tagName == 'code' ||
        element.classes.contains('blockcode');
  }

  bool _isTable(html_dom.Element element) {
    return element.localName?.toLowerCase() == 'table';
  }

  bool _isTableCell(html_dom.Element element) {
    final tagName = element.localName?.toLowerCase();
    return tagName == 'td' || tagName == 'th';
  }

  bool _isContentImage(html_dom.Element element) {
    return element.localName?.toLowerCase() == 'img' &&
        !_isForumStickerImage(element);
  }

  bool _isContentImageOnlyAnchor(html_dom.Element element) {
    if (element.localName?.toLowerCase() != 'a' ||
        element.text.trim().isNotEmpty ||
        element.children.isEmpty) {
      return false;
    }
    return element.children.every(_isContentImage);
  }

  bool _isForumStickerImage(html_dom.Element element) {
    final source = [
      element.attributes['src'],
      element.attributes['data-src'],
      element.attributes['data-original'],
      element.attributes['file'],
      element.attributes['zoomfile'],
    ].whereType<String>().join(' ').toLowerCase();
    return source.contains('static/image/smiley/');
  }

  void _sanitizeStyle(html_dom.Element element) {
    final style = element.attributes['style'];
    if (style == null || style.trim().isEmpty) {
      return;
    }

    final kept = <String>[];
    for (final declaration in style.split(';')) {
      final trimmed = declaration.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex <= 0) {
        kept.add(trimmed);
        continue;
      }
      final property = trimmed.substring(0, colonIndex).trim().toLowerCase();
      if (_shouldDropStyleProperty(property)) {
        continue;
      }
      kept.add(trimmed);
    }

    if (kept.isEmpty) {
      element.attributes.remove('style');
    } else {
      element.attributes['style'] = kept.join('; ');
    }
  }

  void _sanitizeFontElement(html_dom.Element element) {
    if (element.localName?.toLowerCase() != 'font') {
      return;
    }
    if (!preferences.preserveAuthorFontSize) {
      element.attributes.remove('size');
    } else {
      _normalizeDiscuzFontSize(element);
    }
    if (!preferences.preserveAuthorColor) {
      element.attributes.remove('color');
    }
  }

  void _normalizeDiscuzFontSize(html_dom.Element element) {
    final size = element.attributes['size']?.trim();
    if (size == null || size.isEmpty) {
      return;
    }
    element.attributes.remove('size');
    final percent = DiscuzFontSizePolicy.cssPercentFor(size);
    if (percent == null) {
      return;
    }
    _upsertStyleDeclaration(element, 'font-size', percent);
  }

  void _upsertStyleDeclaration(
    html_dom.Element element,
    String property,
    String value,
  ) {
    final targetProperty = property.toLowerCase();
    final declarations = <String>[];
    final style = element.attributes['style'];
    if (style != null && style.trim().isNotEmpty) {
      for (final declaration in style.split(';')) {
        final trimmed = declaration.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        final colonIndex = trimmed.indexOf(':');
        if (colonIndex > 0) {
          final currentProperty = trimmed
              .substring(0, colonIndex)
              .trim()
              .toLowerCase();
          if (currentProperty == targetProperty) {
            continue;
          }
        }
        declarations.add(trimmed);
      }
    }
    declarations.add('$property: $value');
    element.attributes['style'] = declarations.join('; ');
  }

  bool _shouldDropStyleProperty(String property) {
    if (!preferences.preserveAuthorFontSize && property == 'font-size') {
      return true;
    }
    if (!preferences.preserveAuthorColor &&
        (property == 'color' || property == 'font-color')) {
      return true;
    }
    if (!preferences.preserveAuthorBackground &&
        (property == 'background' || property == 'background-color')) {
      return true;
    }
    return false;
  }

  String _serializeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      return node.outerHtml;
    }
    if (node is html_dom.Text) {
      return const HtmlEscape().convert(node.data);
    }
    return node.text ?? '';
  }
}
