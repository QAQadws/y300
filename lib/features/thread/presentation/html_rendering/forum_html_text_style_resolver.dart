import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/reader_shared/domain/rich_text/typography/discuz_font_size_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_author_color_parser.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_inline_style_declarations.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

enum ForumHtmlTextStyleResolutionFailure {
  malformedStyle,
  unsupportedColor,
  unsupportedFontSize,
  unsupportedFontWeight,
  unsupportedFontStyle,
  unsupportedFontFamily,
}

final class ForumHtmlResolvedTextStyle {
  const ForumHtmlResolvedTextStyle.supported(this.style) : failure = null;

  const ForumHtmlResolvedTextStyle.unsupported(this.style, this.failure);

  final TextStyle style;
  final ForumHtmlTextStyleResolutionFailure? failure;

  bool get isSupported => failure == null;
}

/// Resolves the strictly supported inline style subset used by fast layout.
///
/// The final visual authority remains [ForumHtmlWidgetPostRenderer]. This port
/// exists so planning code can reuse the same prepared colors and Discuz font
/// size semantics without adding a novel-specific CSS interpreter.
abstract interface class ForumHtmlTextStyleResolver {
  ForumHtmlResolvedTextStyle resolve({
    required html_dom.Element element,
    required TextStyle parentStyle,
    required TextStyle baseStyle,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
  });
}

final class DefaultForumHtmlTextStyleResolver
    implements ForumHtmlTextStyleResolver {
  const DefaultForumHtmlTextStyleResolver({
    CssInlineStyleDeclarationCodec declarationCodec =
        const CssInlineStyleDeclarationCodec(),
    CssAuthorColorParser colorParser = const CsslibAuthorColorParser(),
  }) : _declarationCodec = declarationCodec,
       _colorParser = colorParser;

  final CssInlineStyleDeclarationCodec _declarationCodec;
  final CssAuthorColorParser _colorParser;

  static const Set<String> _genericFamilies = <String>{
    'sans-serif',
    'serif',
    'monospace',
    'system-ui',
  };

  static const Map<String, String?> _knownFamilies = <String, String?>{
    'arial': 'Arial',
    'simsun': 'SimSun',
    '宋体': 'SimSun',
    'helvetica': 'Helvetica',
    'verdana': 'Verdana',
    'times new roman': 'Times New Roman',
    'courier new': 'Courier New',
    'microsoft yahei': 'Microsoft YaHei',
    'pingfang sc': 'PingFang SC',
    'noto sans cjk sc': 'Noto Sans CJK SC',
    'noto serif cjk sc': 'Noto Serif CJK SC',
  };

  @override
  ForumHtmlResolvedTextStyle resolve({
    required html_dom.Element element,
    required TextStyle parentStyle,
    required TextStyle baseStyle,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
  }) {
    final rawStyle = element.attributes['style'] ?? '';
    final declarations = _declarationCodec.tryParse(rawStyle);
    if (declarations == null) {
      return ForumHtmlResolvedTextStyle.unsupported(
        parentStyle,
        ForumHtmlTextStyleResolutionFailure.malformedStyle,
      );
    }

    var style = _applySemanticStyle(
      element,
      parentStyle,
      baseStyle: baseStyle,
      theme: theme,
    );
    final colors = _colorParser.parseOwn(element);
    if (colors.unsupportedForeground || colors.unsupportedBackground) {
      return ForumHtmlResolvedTextStyle.unsupported(
        style,
        ForumHtmlTextStyleResolutionFailure.unsupportedColor,
      );
    }
    if (colors.foreground != null) {
      style = style.copyWith(color: colors.foreground);
    }
    if (colors.background != null) {
      style = style.copyWith(backgroundColor: colors.background);
    }

    final size = _resolveFontSize(
      element,
      declarations,
      parentStyle: style,
      baseStyle: baseStyle,
      preferences: preferences,
    );
    if (size.failure != null) {
      return ForumHtmlResolvedTextStyle.unsupported(style, size.failure);
    }
    if (size.value != null) {
      style = style.copyWith(fontSize: size.value);
    }

    final weight = _resolveFontWeight(declarations);
    if (weight.failure != null) {
      return ForumHtmlResolvedTextStyle.unsupported(style, weight.failure);
    }
    if (weight.value != null) {
      style = style.copyWith(fontWeight: weight.value);
    }

    final fontStyle = _resolveFontStyle(declarations);
    if (fontStyle.failure != null) {
      return ForumHtmlResolvedTextStyle.unsupported(style, fontStyle.failure);
    }
    if (fontStyle.value != null) {
      style = style.copyWith(fontStyle: fontStyle.value);
    }

    final family = _resolveFontFamily(element, declarations);
    if (family.failure != null) {
      return ForumHtmlResolvedTextStyle.unsupported(style, family.failure);
    }
    if (family.hasValue) {
      style = style.copyWith(fontFamily: family.value);
    }
    return ForumHtmlResolvedTextStyle.supported(style);
  }

  TextStyle _applySemanticStyle(
    html_dom.Element element,
    TextStyle parentStyle, {
    required TextStyle baseStyle,
    required ForumHtmlThemeContext theme,
  }) {
    final tag = element.localName?.toLowerCase();
    var style = parentStyle;
    if (tag == 'strong' || tag == 'b') {
      style = style.copyWith(fontWeight: FontWeight.w700);
    }
    if (tag == 'em' || tag == 'i') {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    if (tag == 'u' || tag == 'a') {
      style = style.copyWith(decoration: TextDecoration.underline);
    }
    if (tag == 'a') {
      style = style.copyWith(color: theme.link);
    }
    if (tag == 'small') {
      style = style.copyWith(fontSize: (style.fontSize ?? 14) * 0.85);
    }
    if (tag == 'mark' && style.backgroundColor == null) {
      style = style.copyWith(backgroundColor: const Color(0x66FFF176));
    }
    final headingLevel = _headingLevel(tag);
    if (headingLevel != null) {
      const scales = <int, double>{
        1: 2,
        2: 1.5,
        3: 1.25,
        4: 1,
        5: 0.875,
        6: 0.75,
      };
      style = style.copyWith(
        fontSize: (baseStyle.fontSize ?? 14) * scales[headingLevel]!,
        fontWeight: FontWeight.w700,
      );
    }
    return style;
  }

  int? _headingLevel(String? tag) {
    if (tag == null || tag.length != 2 || !tag.startsWith('h')) {
      return null;
    }
    final value = int.tryParse(tag.substring(1));
    return value != null && value >= 1 && value <= 6 ? value : null;
  }

  _ResolvedValue<double> _resolveFontSize(
    html_dom.Element element,
    CssInlineStyleDeclarationList declarations, {
    required TextStyle parentStyle,
    required TextStyle baseStyle,
    required ForumHtmlReaderPreferences preferences,
  }) {
    final declaration = declarations.effectiveDeclaration(const <String>{
      'font-size',
    });
    if (declaration != null) {
      final parsed = _fontSizeFromCss(
        declaration.value,
        parentSize: parentStyle.fontSize ?? baseStyle.fontSize ?? 14,
        baseSize: baseStyle.fontSize ?? 14,
      );
      return parsed == null
          ? const _ResolvedValue<double>.failure(
              ForumHtmlTextStyleResolutionFailure.unsupportedFontSize,
            )
          : _ResolvedValue<double>.value(parsed);
    }
    if (element.localName?.toLowerCase() != 'font' ||
        !preferences.preserveAuthorFontSize) {
      return const _ResolvedValue<double>.absent();
    }
    final sizeAttribute = element.attributes['size'];
    if (sizeAttribute == null) {
      return const _ResolvedValue<double>.absent();
    }
    final parsed = DiscuzFontSizePolicy.fontSizeForBase(
      sizeAttribute,
      baseFontSize: baseStyle.fontSize ?? 14,
    );
    return parsed == null
        ? const _ResolvedValue<double>.failure(
            ForumHtmlTextStyleResolutionFailure.unsupportedFontSize,
          )
        : _ResolvedValue<double>.value(parsed);
  }

  double? _fontSizeFromCss(
    String raw, {
    required double parentSize,
    required double baseSize,
  }) {
    final value = raw.trim().toLowerCase();
    double? number(String suffix) =>
        double.tryParse(value.substring(0, value.length - suffix.length));
    if (value.endsWith('%')) {
      final parsed = number('%');
      return parsed == null || parsed <= 0 ? null : parentSize * parsed / 100;
    }
    if (value.endsWith('px')) {
      final parsed = number('px');
      return parsed == null || parsed <= 0 ? null : parsed;
    }
    if (value.endsWith('rem')) {
      final parsed = number('rem');
      return parsed == null || parsed <= 0 ? null : baseSize * parsed;
    }
    if (value.endsWith('em')) {
      final parsed = number('em');
      return parsed == null || parsed <= 0 ? null : parentSize * parsed;
    }
    return null;
  }

  _ResolvedValue<FontWeight> _resolveFontWeight(
    CssInlineStyleDeclarationList declarations,
  ) {
    final value = declarations
        .effectiveDeclaration(const <String>{'font-weight'})
        ?.value
        .trim()
        .toLowerCase();
    if (value == null) {
      return const _ResolvedValue<FontWeight>.absent();
    }
    const weights = <String, FontWeight>{
      'normal': FontWeight.w400,
      'bold': FontWeight.w700,
      '100': FontWeight.w100,
      '200': FontWeight.w200,
      '300': FontWeight.w300,
      '400': FontWeight.w400,
      '500': FontWeight.w500,
      '600': FontWeight.w600,
      '700': FontWeight.w700,
      '800': FontWeight.w800,
      '900': FontWeight.w900,
    };
    final weight = weights[value];
    return weight == null
        ? const _ResolvedValue<FontWeight>.failure(
            ForumHtmlTextStyleResolutionFailure.unsupportedFontWeight,
          )
        : _ResolvedValue<FontWeight>.value(weight);
  }

  _ResolvedValue<FontStyle> _resolveFontStyle(
    CssInlineStyleDeclarationList declarations,
  ) {
    final value = declarations
        .effectiveDeclaration(const <String>{'font-style'})
        ?.value
        .trim()
        .toLowerCase();
    if (value == null) {
      return const _ResolvedValue<FontStyle>.absent();
    }
    if (value == 'normal') {
      return const _ResolvedValue<FontStyle>.value(FontStyle.normal);
    }
    if (value == 'italic' || value == 'oblique') {
      return const _ResolvedValue<FontStyle>.value(FontStyle.italic);
    }
    return const _ResolvedValue<FontStyle>.failure(
      ForumHtmlTextStyleResolutionFailure.unsupportedFontStyle,
    );
  }

  _ResolvedFontFamily _resolveFontFamily(
    html_dom.Element element,
    CssInlineStyleDeclarationList declarations,
  ) {
    final declared = declarations.effectiveDeclaration(const <String>{
      'font-family',
    })?.value;
    final raw =
        declared ??
        (element.localName?.toLowerCase() == 'font'
            ? element.attributes['face']
            : null);
    if (raw == null) {
      return const _ResolvedFontFamily.absent();
    }
    final candidates = raw
        .split(',')
        .map(_normalizeFamily)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return const _ResolvedFontFamily.failure();
    }
    for (final candidate in candidates) {
      if (_genericFamilies.contains(candidate)) {
        return const _ResolvedFontFamily.value(null);
      }
      final mapped = _knownFamilies[candidate];
      if (mapped != null) {
        return _ResolvedFontFamily.value(mapped);
      }
    }
    return const _ResolvedFontFamily.failure();
  }

  String _normalizeFamily(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'''^["']|["']$'''), '')
        .trim()
        .toLowerCase();
  }
}

final class _ResolvedValue<T> {
  const _ResolvedValue.absent() : value = null, failure = null;
  const _ResolvedValue.value(this.value) : failure = null;
  const _ResolvedValue.failure(this.failure) : value = null;

  final T? value;
  final ForumHtmlTextStyleResolutionFailure? failure;
}

final class _ResolvedFontFamily {
  const _ResolvedFontFamily.absent()
    : value = null,
      hasValue = false,
      failure = null;
  const _ResolvedFontFamily.value(this.value) : hasValue = true, failure = null;
  const _ResolvedFontFamily.failure()
    : value = null,
      hasValue = false,
      failure = ForumHtmlTextStyleResolutionFailure.unsupportedFontFamily;

  final String? value;
  final bool hasValue;
  final ForumHtmlTextStyleResolutionFailure? failure;
}
