import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
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
    if (_isParagraphLike(element)) {
      return {'margin': '0 0 ${preferences.typography.paragraphSpacing}px'};
    }
    return null;
  }

  String prepareHtml(String html) {
    if (preferences.preserveAuthorFontSize &&
        preferences.preserveAuthorColor &&
        preferences.preserveAuthorBackground) {
      return html;
    }

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
    }
    if (!preferences.preserveAuthorColor) {
      element.attributes.remove('color');
    }
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
