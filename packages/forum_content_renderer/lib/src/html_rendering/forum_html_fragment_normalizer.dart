import 'package:html/dom.dart' as html_dom;

import '../helpers/discuz_font_size_policy.dart';
import '../models/forum_html_render_options.dart';
import 'theme/css_inline_style_declarations.dart';

/// Normalizes the shared Discuz fragment before either renderer reads it.
final class ForumHtmlFragmentNormalizer {
  ForumHtmlFragmentNormalizer(this._options);

  final ForumHtmlRenderOptions _options;
  final _inlineStyleDeclarationCodec = CssInlineStyleDeclarationCodec.scoped();

  void normalize(html_dom.DocumentFragment fragment) {
    _normalizeStructure(fragment);
    _normalizeAuthorStyles(fragment);
  }

  void _normalizeStructure(html_dom.DocumentFragment fragment) {
    for (final editStatus in fragment.querySelectorAll('.pstatus')) {
      _normalizeEditStatusSpacing(editStatus);
    }
  }

  void _normalizeAuthorStyles(html_dom.DocumentFragment fragment) {
    if (!_options.preserveAuthorFontSize ||
        !_options.preserveAuthorFontFamily) {
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
    if (!_options.preserveAuthorFontFamily) {
      element.attributes.remove('face');
    }
    if (!_options.preserveAuthorFontSize) {
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
    return !_options.preserveAuthorFontSize && property == 'font-size' ||
        !_options.preserveAuthorFontFamily && property == 'font-family';
  }
}
