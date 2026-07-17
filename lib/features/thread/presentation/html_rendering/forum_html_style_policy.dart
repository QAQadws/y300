import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/reader_shared/domain/rich_text/typography/discuz_font_size_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_inline_style_declarations.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

class ForumHtmlStylePolicy {
  const ForumHtmlStylePolicy(
    this.preferences, {
    required this.theme,
    CssInlineStyleDeclarationCodec inlineStyleDeclarationCodec =
        const CssInlineStyleDeclarationCodec(),
  }) : _inlineStyleDeclarationCodec = inlineStyleDeclarationCodec;

  final ForumHtmlReaderPreferences preferences;
  final ForumHtmlThemeContext theme;
  final CssInlineStyleDeclarationCodec _inlineStyleDeclarationCodec;

  TextStyle baseTextStyle(BuildContext context) {
    final fallback = Theme.of(context).textTheme.bodyMedium;
    final baseFontSize = fallback?.fontSize ?? 14;
    return (fallback ?? const TextStyle()).copyWith(
      color: theme.foreground,
      fontSize: baseFontSize * preferences.typography.fontScale,
      height: preferences.typography.lineHeightScale,
    );
  }

  StylesMap? customStylesFor(html_dom.Element element) {
    if (isForumCollapseElement(element) ||
        isForumCollapseGatherElement(element)) {
      return {'display': 'none'};
    }
    if (_isQuoteSurface(element)) {
      return {
        'background-color': _toCssHex(theme.quoteSurface),
        'color': _toCssHex(theme.quoteForeground),
        'border-left': '3px solid ${_toCssHex(theme.link)}',
        'border-radius': '6px',
        'padding': '8px 10px',
        'margin': '0 0 ${preferences.typography.paragraphSpacing}px',
      };
    }
    if (_isQuoteBodyInsideSurface(element)) {
      return {'margin': '0'};
    }
    if (_isCodeLike(element)) {
      return {
        'background-color': _toCssHex(theme.codeSurface),
        'color': _toCssHex(theme.codeForeground),
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

  void prepareFragment(html_dom.DocumentFragment fragment) {
    normalizeStructure(fragment);
    normalizeAuthorStyles(fragment);
  }

  void normalizeStructure(html_dom.DocumentFragment fragment) {
    for (final editStatus in fragment.querySelectorAll('.pstatus')) {
      _normalizeEditStatusSpacing(editStatus);
    }
  }

  void normalizeAuthorStyles(html_dom.DocumentFragment fragment) {
    if (!preferences.preserveAuthorFontSize) {
      for (final element in fragment.querySelectorAll('[style]')) {
        _sanitizeStyle(element);
      }
    }
    for (final element in fragment.querySelectorAll('font')) {
      _sanitizeFontElement(element);
    }
  }

  void _normalizeEditStatusSpacing(html_dom.Element editStatus) {
    final parent = editStatus.parentNode;
    if (parent == null) {
      return;
    }
    final editStatusIndex = parent.nodes.indexOf(editStatus);
    if (editStatusIndex < 0) {
      return;
    }
    final removable = <html_dom.Node>[];
    var hasStructuralBreak = false;
    for (
      var index = editStatusIndex + 1;
      index < parent.nodes.length;
      index++
    ) {
      final sibling = parent.nodes[index];
      final isWhitespace =
          sibling is html_dom.Text && sibling.data.trim().isEmpty;
      final isBreak =
          sibling is html_dom.Element &&
          sibling.localName?.toLowerCase() == 'br';
      if (!isWhitespace && !isBreak) {
        break;
      }
      removable.add(sibling);
      hasStructuralBreak = hasStructuralBreak || isBreak;
    }
    if (!hasStructuralBreak) {
      return;
    }
    for (final node in removable) {
      node.remove();
    }
  }

  bool _isParagraphLike(html_dom.Element element) {
    final tagName = element.localName?.toLowerCase();
    return tagName == 'p' || tagName == 'div' || tagName == 'blockquote';
  }

  bool _isQuoteSurface(html_dom.Element element) {
    if (element.classes.contains('quote')) {
      return true;
    }
    return element.localName?.toLowerCase() == 'blockquote' &&
        !_hasQuoteContainerAncestor(element);
  }

  bool _isQuoteBodyInsideSurface(html_dom.Element element) {
    return element.localName?.toLowerCase() == 'blockquote' &&
        _hasQuoteContainerAncestor(element);
  }

  bool _hasQuoteContainerAncestor(html_dom.Element element) {
    html_dom.Node? ancestor = element.parentNode;
    while (ancestor != null) {
      if (ancestor is html_dom.Element && ancestor.classes.contains('quote')) {
        return true;
      }
      ancestor = ancestor.parentNode;
    }
    return false;
  }

  String _toCssHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
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
    final parsed = _inlineStyleDeclarationCodec.tryParse(style);
    if (parsed == null) {
      return;
    }
    final kept = CssInlineStyleDeclarationList(
      parsed.declarations.where(
        (declaration) => !_shouldDropStyleProperty(declaration.property),
      ),
    );
    if (kept.declarations.length == parsed.declarations.length) {
      return;
    }
    if (kept.declarations.isEmpty) {
      element.attributes.remove('style');
    } else {
      element.attributes['style'] = kept.toCss();
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
  }

  void _normalizeDiscuzFontSize(html_dom.Element element) {
    final size = element.attributes['size']?.trim();
    if (size == null || size.isEmpty) {
      return;
    }
    final percent = DiscuzFontSizePolicy.cssPercentFor(size);
    if (percent == null) {
      element.attributes.remove('size');
      return;
    }
    if (_upsertStyleDeclaration(element, 'font-size', percent)) {
      element.attributes.remove('size');
    }
  }

  bool _upsertStyleDeclaration(
    html_dom.Element element,
    String property,
    String value,
  ) {
    final parsed = _inlineStyleDeclarationCodec.tryParse(
      element.attributes['style'] ?? '',
    );
    if (parsed == null) {
      return false;
    }
    element.attributes['style'] = parsed
        .upsert(property: property, value: value)
        .toCss();
    return true;
  }

  bool _shouldDropStyleProperty(String property) {
    return !preferences.preserveAuthorFontSize && property == 'font-size';
  }
}
