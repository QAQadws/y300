import 'dart:ui';

import 'package:csslib/visitor.dart' as css_ast;
import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/thread/presentation/html_rendering/theme/css_inline_style_declarations.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_author_color_style.dart';

abstract interface class CssAuthorColorParser {
  ForumHtmlAuthorColorStyle parse(html_dom.Element element);

  ForumHtmlAuthorColorStyle parseOwn(html_dom.Element element);
}

final class CsslibAuthorColorParser implements CssAuthorColorParser {
  const CsslibAuthorColorParser({
    CssInlineStyleDeclarationCodec declarationCodec =
        const CssInlineStyleDeclarationCodec(),
  }) : _declarationCodec = declarationCodec;

  static const _blockTags = <String>{
    'article',
    'aside',
    'blockquote',
    'div',
    'footer',
    'header',
    'li',
    'ol',
    'p',
    'pre',
    'section',
    'table',
    'tbody',
    'td',
    'tfoot',
    'th',
    'thead',
    'tr',
    'ul',
  };

  final CssInlineStyleDeclarationCodec _declarationCodec;

  @override
  ForumHtmlAuthorColorStyle parse(html_dom.Element element) {
    final own = parseOwn(element);
    var foreground = own.foreground;
    var foregroundSource = own.foregroundSource;
    var background = own.background;
    var backgroundSource = own.backgroundSource;

    html_dom.Node? ancestor = element.parentNode;
    while (ancestor is html_dom.Element &&
        (foreground == null || background == null)) {
      final ancestorStyle = parseOwn(ancestor);
      if (foreground == null && ancestorStyle.foreground != null) {
        foreground = ancestorStyle.foreground;
        foregroundSource = ForumHtmlColorSource.inherited;
      }
      if (background == null && ancestorStyle.background != null) {
        background = ancestorStyle.background;
        backgroundSource = ForumHtmlColorSource.inherited;
      }
      ancestor = ancestor.parentNode;
    }

    return ForumHtmlAuthorColorStyle(
      foreground: foreground,
      background: background,
      foregroundSource: foregroundSource,
      backgroundSource: backgroundSource,
      backgroundRole: _backgroundRoleFor(element),
      unsupportedForeground: own.unsupportedForeground,
      unsupportedBackground: own.unsupportedBackground,
      transparentForeground: own.transparentForeground,
      transparentBackground: own.transparentBackground,
    );
  }

  @override
  ForumHtmlAuthorColorStyle parseOwn(html_dom.Element element) {
    final own = _parseOwn(element);
    return ForumHtmlAuthorColorStyle(
      foreground: own.foreground,
      background: own.background,
      foregroundSource: own.foregroundSource,
      backgroundSource: own.backgroundSource,
      backgroundRole: _backgroundRoleFor(element),
      unsupportedForeground: own.unsupportedForeground,
      unsupportedBackground: own.unsupportedBackground,
      transparentForeground: own.transparentForeground,
      transparentBackground: own.transparentBackground,
    );
  }

  _OwnAuthorColors _parseOwn(html_dom.Element element) {
    final declarations = _declarationCodec.tryParse(
      element.attributes['style'] ?? '',
    );
    final inlineForeground = declarations?.effectiveDeclaration(const <String>{
      'color',
    });
    final inlineBackground = declarations?.effectiveDeclaration(const <String>{
      'background',
      'background-color',
    });
    final inlineForegroundResult = _parseDeclaration(inlineForeground);
    final inlineBackgroundResult = _parseDeclaration(inlineBackground);

    final legacyForeground = element.localName?.toLowerCase() == 'font'
        ? _parseLegacyColor(element.attributes['color'], 'color')
        : const _ParsedColor.absent();
    final legacyBackground = _parseLegacyColor(
      element.attributes['bgcolor'],
      'background-color',
    );

    final hasInlineForeground = inlineForeground != null;
    final hasInlineBackground = inlineBackground != null;
    final foreground = hasInlineForeground
        ? inlineForegroundResult.color
        : legacyForeground.color;
    final background = hasInlineBackground
        ? inlineBackgroundResult.color
        : legacyBackground.color;
    return _OwnAuthorColors(
      foreground: foreground,
      background: background,
      foregroundSource: hasInlineForeground
          ? inlineForegroundResult.color != null
                ? ForumHtmlColorSource.inlineStyle
                : null
          : legacyForeground.color != null
          ? ForumHtmlColorSource.legacyFontAttribute
          : null,
      backgroundSource: hasInlineBackground
          ? inlineBackgroundResult.color != null
                ? ForumHtmlColorSource.inlineStyle
                : null
          : legacyBackground.color != null
          ? ForumHtmlColorSource.legacyBgColorAttribute
          : null,
      unsupportedForeground: hasInlineForeground
          ? inlineForegroundResult.unsupported
          : legacyForeground.unsupported,
      unsupportedBackground: hasInlineBackground
          ? inlineBackgroundResult.unsupported
          : legacyBackground.unsupported,
      transparentForeground: hasInlineForeground
          ? inlineForegroundResult.transparent
          : legacyForeground.transparent,
      transparentBackground: hasInlineBackground
          ? inlineBackgroundResult.transparent
          : legacyBackground.transparent,
    );
  }

  _ParsedColor _parseLegacyColor(String? raw, String property) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return const _ParsedColor.absent();
    }
    final declarations = _declarationCodec.tryParse('$property: $value');
    return _parseDeclaration(
      declarations?.effectiveDeclaration(<String>{property}),
      declared: true,
    );
  }

  _ParsedColor _parseDeclaration(
    CssInlineStyleDeclaration? declaration, {
    bool declared = false,
  }) {
    if (declaration == null) {
      return declared
          ? const _ParsedColor.unsupported()
          : const _ParsedColor.absent();
    }
    final raw = declaration.value.trim();
    final normalized = raw.toLowerCase();
    if (normalized.startsWith('var(')) {
      return const _ParsedColor.unsupported();
    }
    if (normalized == 'transparent') {
      return const _ParsedColor.transparent();
    }
    if (raw.startsWith('#')) {
      return _parseHex(raw);
    }
    final expression = declaration.expression;
    if (expression == null) {
      return const _ParsedColor.unsupported();
    }
    try {
      final visitor = _CssColorExpressionVisitor();
      expression.visit(visitor);
      final color = visitor.resolve();
      if (color == null) {
        return const _ParsedColor.unsupported();
      }
      if ((color.toARGB32() >>> 24) == 0) {
        return const _ParsedColor.transparent();
      }
      return _ParsedColor.color(color);
    } catch (_) {
      return const _ParsedColor.unsupported();
    }
  }

  _ParsedColor _parseHex(String raw) {
    final hex = raw.substring(1);
    if (!const <int>{3, 4, 6, 8}.contains(hex.length) ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      return const _ParsedColor.unsupported();
    }
    int component(String value) => int.parse(value, radix: 16);
    late final int red;
    late final int green;
    late final int blue;
    late final int alpha;
    if (hex.length == 3 || hex.length == 4) {
      red = component('${hex[0]}${hex[0]}');
      green = component('${hex[1]}${hex[1]}');
      blue = component('${hex[2]}${hex[2]}');
      alpha = hex.length == 4 ? component('${hex[3]}${hex[3]}') : 0xFF;
    } else {
      red = component(hex.substring(0, 2));
      green = component(hex.substring(2, 4));
      blue = component(hex.substring(4, 6));
      alpha = hex.length == 8 ? component(hex.substring(6, 8)) : 0xFF;
    }
    if (alpha == 0) {
      return const _ParsedColor.transparent();
    }
    return _ParsedColor.color(Color.fromARGB(alpha, red, green, blue));
  }

  ForumHtmlBackgroundRole _backgroundRoleFor(html_dom.Element element) {
    return _blockTags.contains(element.localName?.toLowerCase())
        ? ForumHtmlBackgroundRole.blockSurface
        : ForumHtmlBackgroundRole.inlineHighlight;
  }
}

final class _OwnAuthorColors {
  const _OwnAuthorColors({
    required this.foreground,
    required this.background,
    required this.foregroundSource,
    required this.backgroundSource,
    required this.unsupportedForeground,
    required this.unsupportedBackground,
    required this.transparentForeground,
    required this.transparentBackground,
  });

  final Color? foreground;
  final Color? background;
  final ForumHtmlColorSource? foregroundSource;
  final ForumHtmlColorSource? backgroundSource;
  final bool unsupportedForeground;
  final bool unsupportedBackground;
  final bool transparentForeground;
  final bool transparentBackground;
}

final class _ParsedColor {
  const _ParsedColor.absent()
    : color = null,
      unsupported = false,
      transparent = false;

  const _ParsedColor.color(this.color)
    : unsupported = false,
      transparent = false;

  const _ParsedColor.unsupported()
    : color = null,
      unsupported = true,
      transparent = false;

  const _ParsedColor.transparent()
    : color = null,
      unsupported = false,
      transparent = true;

  final Color? color;
  final bool unsupported;
  final bool transparent;
}

final class _CssColorExpressionVisitor extends css_ast.Visitor {
  final _hexTerms = <css_ast.HexColorTerm>[];
  final _functionNames = <String>[];
  final _components = <_CssColorComponent>[];
  var _hasOtherTerms = false;

  @override
  void visitHexColorTerm(css_ast.HexColorTerm node) {
    _hexTerms.add(node);
  }

  @override
  void visitFunctionTerm(css_ast.FunctionTerm node) {
    _functionNames.add(node.text.toLowerCase());
    super.visitFunctionTerm(node);
  }

  @override
  void visitNumberTerm(css_ast.NumberTerm node) {
    final value = node.value;
    if (value is num) {
      _components.add(_CssColorComponent(value.toDouble(), false));
    } else {
      _hasOtherTerms = true;
    }
  }

  @override
  void visitPercentageTerm(css_ast.PercentageTerm node) {
    final value = node.value;
    if (value is num) {
      _components.add(_CssColorComponent(value.toDouble(), true));
    } else {
      _hasOtherTerms = true;
    }
  }

  @override
  void visitLiteralTerm(css_ast.LiteralTerm node) {
    if (node is! css_ast.FunctionTerm) {
      _hasOtherTerms = true;
    }
  }

  Color? resolve() {
    if (_functionNames.isEmpty) {
      if (_hasOtherTerms || _hexTerms.length != 1 || _components.isNotEmpty) {
        return null;
      }
      final term = _hexTerms.single;
      final hex = term.text;
      if (!const <int>{3, 6}.contains(hex.length)) {
        return null;
      }
      final expanded = hex.length == 3
          ? '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}'
          : hex;
      final rgb = int.tryParse(expanded, radix: 16);
      return rgb == null ? null : Color(0xFF000000 | rgb);
    }
    if (_hasOtherTerms || _functionNames.length != 1 || _hexTerms.isNotEmpty) {
      return null;
    }
    final function = _functionNames.single;
    if (function != 'rgb' && function != 'rgba') {
      return null;
    }
    final expectedLength = function == 'rgb' ? 3 : 4;
    if (_components.length != expectedLength) {
      return null;
    }
    final red = _rgbByte(_components[0]);
    final green = _rgbByte(_components[1]);
    final blue = _rgbByte(_components[2]);
    final alpha = function == 'rgba' ? _alphaByte(_components[3]) : 0xFF;
    return Color.fromARGB(alpha, red, green, blue);
  }

  int _rgbByte(_CssColorComponent component) {
    final value = component.percentage
        ? component.value.clamp(0, 100) * 255 / 100
        : component.value.clamp(0, 255);
    return value.round();
  }

  int _alphaByte(_CssColorComponent component) {
    final value = component.percentage
        ? component.value.clamp(0, 100) / 100
        : component.value.clamp(0, 1);
    return (value * 255).round();
  }
}

final class _CssColorComponent {
  const _CssColorComponent(this.value, this.percentage);

  final double value;
  final bool percentage;
}
