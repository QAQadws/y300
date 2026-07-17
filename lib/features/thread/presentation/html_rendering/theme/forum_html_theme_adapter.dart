import 'dart:ui';

import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/reader_shared/presentation/rich_text/color/rich_text_color_contrast.dart';
import 'package:y300/features/reader_shared/presentation/rich_text/color/rich_text_tone_resolver.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_author_color_parser.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_inline_style_declarations.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_background_tone_resolver.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_author_color_style.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_color_adaptation_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_resolved_color_state.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_adaptation_result.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

abstract interface class ForumHtmlThemeAdapter {
  ForumHtmlThemeAdaptationResult adapt({
    required html_dom.DocumentFragment fragment,
    required ForumHtmlThemeContext theme,
    required ForumHtmlColorAdaptationPolicy policy,
  });
}

final class DefaultForumHtmlThemeAdapter implements ForumHtmlThemeAdapter {
  const DefaultForumHtmlThemeAdapter({
    CssAuthorColorParser colorParser = const CsslibAuthorColorParser(),
    CssInlineStyleDeclarationCodec declarationCodec =
        const CssInlineStyleDeclarationCodec(),
    ForumHtmlBackgroundToneResolver backgroundToneResolver =
        const MaterialForumHtmlBackgroundToneResolver(),
    RichTextToneResolver toneResolver = const MaterialRichTextToneResolver(),
    RichTextColorContrast contrast = const FlutterRichTextColorContrast(),
  }) : _colorParser = colorParser,
       _declarationCodec = declarationCodec,
       _backgroundToneResolver = backgroundToneResolver,
       _toneResolver = toneResolver,
       _contrast = contrast;

  static const _foregroundProperties = <String>{'color'};
  static const _backgroundProperties = <String>{
    'background',
    'background-color',
  };

  final CssAuthorColorParser _colorParser;
  final CssInlineStyleDeclarationCodec _declarationCodec;
  final ForumHtmlBackgroundToneResolver _backgroundToneResolver;
  final RichTextToneResolver _toneResolver;
  final RichTextColorContrast _contrast;

  @override
  ForumHtmlThemeAdaptationResult adapt({
    required html_dom.DocumentFragment fragment,
    required ForumHtmlThemeContext theme,
    required ForumHtmlColorAdaptationPolicy policy,
  }) {
    final stats = _MutableThemeAdaptationStats();
    final rootState = _TraversalColorState(
      resolved: ForumHtmlResolvedColorState(
        effectiveForeground: theme.foreground,
        effectiveBackground: theme.surface,
        semanticRole: ForumHtmlSemanticColorRole.body,
      ),
      originalBackground: theme.surface,
      concealed: false,
    );
    for (final child in fragment.children.toList(growable: false)) {
      _visit(
        element: child,
        parent: rootState,
        theme: theme,
        policy: policy,
        stats: stats,
      );
    }
    return ForumHtmlThemeAdaptationResult(
      fragment: fragment,
      stats: stats.build(),
    );
  }

  void _visit({
    required html_dom.Element element,
    required _TraversalColorState parent,
    required ForumHtmlThemeContext theme,
    required ForumHtmlColorAdaptationPolicy policy,
    required _MutableThemeAdaptationStats stats,
  }) {
    var current = parent;
    try {
      current = _adaptElement(
        element: element,
        parent: parent,
        theme: theme,
        policy: policy,
        stats: stats,
      );
    } catch (_) {
      stats.semanticFallbackCount++;
      _neutralizeElement(element);
      final role = _semanticRole(element, parent.resolved.semanticRole);
      current = _TraversalColorState(
        resolved: ForumHtmlResolvedColorState(
          effectiveForeground: _semanticForeground(role, theme),
          effectiveBackground:
              _ownedSurface(element, theme) ??
              parent.resolved.effectiveBackground,
          semanticRole: role,
        ),
        originalBackground: parent.originalBackground,
        concealed: false,
      );
    }
    for (final child in element.children.toList(growable: false)) {
      _visit(
        element: child,
        parent: current,
        theme: theme,
        policy: policy,
        stats: stats,
      );
    }
  }

  _TraversalColorState _adaptElement({
    required html_dom.Element element,
    required _TraversalColorState parent,
    required ForumHtmlThemeContext theme,
    required ForumHtmlColorAdaptationPolicy policy,
    required _MutableThemeAdaptationStats stats,
  }) {
    final author = _colorParser.parseOwn(element);
    final role = _semanticRole(element, parent.resolved.semanticRole);
    final semanticForeground = _semanticForeground(role, theme);
    final ownedSurface = _ownedSurface(element, theme);
    final hasForegroundDeclaration =
        author.foreground != null ||
        author.unsupportedForeground ||
        author.transparentForeground;
    final hasBackgroundDeclaration =
        author.background != null ||
        author.unsupportedBackground ||
        author.transparentBackground;
    final originalBackground = author.background == null
        ? parent.originalBackground
        : _contrast.composite(author.background!, parent.originalBackground);

    if (ownedSurface != null || role == ForumHtmlSemanticColorRole.editStatus) {
      final background = ownedSurface ?? parent.resolved.effectiveBackground;
      _recordOwnedDeclarations(author, semanticForeground, background, stats);
      if (hasForegroundDeclaration) {
        _rewriteForeground(element, null);
      }
      if (hasBackgroundDeclaration) {
        _rewriteBackground(element, null);
      }
      final state = _TraversalColorState(
        resolved: ForumHtmlResolvedColorState(
          effectiveForeground: semanticForeground,
          effectiveBackground: background,
          semanticRole: role,
        ),
        originalBackground: originalBackground,
        concealed: false,
      );
      _recordContrastForDirectText(element, state, stats);
      return state;
    }

    var background = parent.resolved.effectiveBackground;
    if (author.background != null) {
      stats.explicitBackgroundCount++;
      try {
        background = _backgroundToneResolver.resolve(
          requested: originalBackground,
          role: author.backgroundRole,
          theme: theme,
          policy: policy,
        );
        _rewriteBackground(element, background);
        if (background.toARGB32() != originalBackground.toARGB32()) {
          stats.remappedBackgroundCount++;
        }
      } catch (_) {
        stats.semanticFallbackCount++;
        _rewriteBackground(element, null);
      }
    } else if (author.unsupportedBackground) {
      stats.unsupportedColorCount++;
      stats.semanticFallbackCount++;
      _rewriteBackground(element, null);
    } else if (author.transparentBackground) {
      _rewriteBackground(element, null);
    }

    final declaresConcealedText =
        author.foreground != null &&
        author.background != null &&
        element.text.trim().isNotEmpty &&
        _colorsNearlyEqual(
          _contrast.composite(author.foreground!, originalBackground),
          originalBackground,
        );
    final inheritsConcealedText =
        parent.concealed &&
        !hasForegroundDeclaration &&
        !hasBackgroundDeclaration &&
        background.toARGB32() == parent.resolved.effectiveBackground.toARGB32();

    if (declaresConcealedText || inheritsConcealedText) {
      if (author.foreground != null) {
        stats.explicitForegroundCount++;
        if (author.foreground!.toARGB32() != background.toARGB32()) {
          stats.remappedForegroundCount++;
        }
      }
      if (declaresConcealedText) {
        stats.concealedTextRangeCount++;
      }
      if (declaresConcealedText || role == ForumHtmlSemanticColorRole.link) {
        _rewriteForeground(element, background);
      }
      return _TraversalColorState(
        resolved: ForumHtmlResolvedColorState(
          effectiveForeground: background,
          effectiveBackground: background,
          semanticRole: ForumHtmlSemanticColorRole.concealedText,
        ),
        originalBackground: originalBackground,
        concealed: true,
      );
    }

    var requestedForeground = parent.resolved.effectiveForeground;
    var shouldWriteForeground = false;
    if (author.foreground != null) {
      stats.explicitForegroundCount++;
      requestedForeground = author.foreground!;
      shouldWriteForeground = true;
    } else if (author.unsupportedForeground) {
      stats.unsupportedColorCount++;
      stats.semanticFallbackCount++;
      requestedForeground = semanticForeground;
      shouldWriteForeground = true;
    } else if (author.transparentForeground) {
      _rewriteForeground(element, null);
    } else if (role != parent.resolved.semanticRole) {
      requestedForeground = semanticForeground;
      shouldWriteForeground = true;
    }

    final foreground = _resolveForeground(
      requested: requestedForeground,
      background: background,
      fallback: semanticForeground,
      policy: policy,
      stats: stats,
    );
    if (author.foreground != null &&
        foreground.toARGB32() != author.foreground!.toARGB32()) {
      stats.remappedForegroundCount++;
    }
    if (foreground.toARGB32() != requestedForeground.toARGB32()) {
      shouldWriteForeground = true;
    }
    if (shouldWriteForeground) {
      _rewriteForeground(element, foreground);
    }

    final state = _TraversalColorState(
      resolved: ForumHtmlResolvedColorState(
        effectiveForeground: foreground,
        effectiveBackground: background,
        semanticRole: role,
      ),
      originalBackground: originalBackground,
      concealed: false,
    );
    _recordContrastForDirectText(element, state, stats);
    return state;
  }

  Color _resolveForeground({
    required Color requested,
    required Color background,
    required Color fallback,
    required ForumHtmlColorAdaptationPolicy policy,
    required _MutableThemeAdaptationStats stats,
  }) {
    try {
      return _toneResolver.resolveReadableForeground(
        requested: requested,
        background: background,
        fallback: fallback,
        minimumContrast: policy.minimumTextContrast,
      );
    } catch (_) {
      stats.semanticFallbackCount++;
      return fallback;
    }
  }

  void _recordOwnedDeclarations(
    ForumHtmlAuthorColorStyle author,
    Color foreground,
    Color background,
    _MutableThemeAdaptationStats stats,
  ) {
    if (author.foreground != null) {
      stats.explicitForegroundCount++;
      if (author.foreground!.toARGB32() != foreground.toARGB32()) {
        stats.remappedForegroundCount++;
      }
    } else if (author.unsupportedForeground) {
      stats.unsupportedColorCount++;
      stats.semanticFallbackCount++;
    }
    if (author.background != null) {
      stats.explicitBackgroundCount++;
      if (author.background!.toARGB32() != background.toARGB32()) {
        stats.remappedBackgroundCount++;
      }
    } else if (author.unsupportedBackground) {
      stats.unsupportedColorCount++;
      stats.semanticFallbackCount++;
    }
  }

  void _recordContrastForDirectText(
    html_dom.Element element,
    _TraversalColorState state,
    _MutableThemeAdaptationStats stats,
  ) {
    final hasDirectText = element.nodes.whereType<html_dom.Text>().any(
      (node) => node.data.trim().isNotEmpty,
    );
    if (!hasDirectText || state.concealed) {
      return;
    }
    final visibleForeground = _contrast.composite(
      state.resolved.effectiveForeground,
      state.resolved.effectiveBackground,
    );
    stats.recordContrast(
      _contrast.contrastRatio(
        visibleForeground,
        state.resolved.effectiveBackground,
      ),
    );
  }

  ForumHtmlSemanticColorRole _semanticRole(
    html_dom.Element element,
    ForumHtmlSemanticColorRole parent,
  ) {
    if (element.classes.contains('pstatus')) {
      return ForumHtmlSemanticColorRole.editStatus;
    }
    if (_isCodeLike(element)) {
      return ForumHtmlSemanticColorRole.code;
    }
    if (_isQuoteSurface(element)) {
      return ForumHtmlSemanticColorRole.quote;
    }
    if (element.localName?.toLowerCase() == 'a') {
      return ForumHtmlSemanticColorRole.link;
    }
    if (parent == ForumHtmlSemanticColorRole.quote ||
        parent == ForumHtmlSemanticColorRole.code) {
      return parent;
    }
    return ForumHtmlSemanticColorRole.body;
  }

  Color _semanticForeground(
    ForumHtmlSemanticColorRole role,
    ForumHtmlThemeContext theme,
  ) {
    return switch (role) {
      ForumHtmlSemanticColorRole.link => theme.link,
      ForumHtmlSemanticColorRole.quote => theme.quoteForeground,
      ForumHtmlSemanticColorRole.code => theme.codeForeground,
      ForumHtmlSemanticColorRole.body ||
      ForumHtmlSemanticColorRole.editStatus ||
      ForumHtmlSemanticColorRole.concealedText => theme.foreground,
    };
  }

  Color? _ownedSurface(html_dom.Element element, ForumHtmlThemeContext theme) {
    if (_isQuoteSurface(element)) {
      return theme.quoteSurface;
    }
    if (_isCodeLike(element)) {
      return theme.codeSurface;
    }
    return null;
  }

  bool _isQuoteSurface(html_dom.Element element) {
    if (element.classes.contains('quote')) {
      return true;
    }
    if (element.localName?.toLowerCase() != 'blockquote') {
      return false;
    }
    html_dom.Node? ancestor = element.parentNode;
    while (ancestor is html_dom.Element) {
      if (ancestor.classes.contains('quote')) {
        return false;
      }
      ancestor = ancestor.parentNode;
    }
    return true;
  }

  bool _isCodeLike(html_dom.Element element) {
    final tagName = element.localName?.toLowerCase();
    return tagName == 'pre' ||
        tagName == 'code' ||
        element.classes.contains('blockcode');
  }

  bool _colorsNearlyEqual(Color first, Color second) {
    int channel(int argb, int shift) => (argb >> shift) & 0xFF;
    final firstArgb = first.toARGB32();
    final secondArgb = second.toARGB32();
    return (channel(firstArgb, 16) - channel(secondArgb, 16)).abs() <= 4 &&
        (channel(firstArgb, 8) - channel(secondArgb, 8)).abs() <= 4 &&
        (channel(firstArgb, 0) - channel(secondArgb, 0)).abs() <= 4;
  }

  void _rewriteForeground(html_dom.Element element, Color? color) {
    _rewriteDeclarations(
      element,
      properties: _foregroundProperties,
      replacementProperty: color == null ? null : 'color',
      replacementValue: color == null ? null : _toCssColor(color),
    );
    if (element.localName?.toLowerCase() == 'font') {
      element.attributes.remove('color');
    }
  }

  void _rewriteBackground(html_dom.Element element, Color? color) {
    _rewriteDeclarations(
      element,
      properties: _backgroundProperties,
      replacementProperty: color == null ? null : 'background-color',
      replacementValue: color == null ? null : _toCssColor(color),
    );
    element.attributes.remove('bgcolor');
  }

  void _rewriteDeclarations(
    html_dom.Element element, {
    required Set<String> properties,
    required String? replacementProperty,
    required String? replacementValue,
  }) {
    final rawStyle = element.attributes['style'] ?? '';
    final parsed = _declarationCodec.tryParse(rawStyle);
    if (parsed == null) {
      return;
    }
    var declarations = parsed.withoutProperties(properties);
    if (replacementProperty != null && replacementValue != null) {
      declarations = declarations.upsert(
        property: replacementProperty,
        value: replacementValue,
      );
    }
    if (declarations.declarations.isEmpty) {
      element.attributes.remove('style');
    } else {
      element.attributes['style'] = declarations.toCss();
    }
  }

  String _toCssColor(Color color) {
    final argb = color.toARGB32();
    final alpha = (argb >>> 24) & 0xFF;
    final red = (argb >>> 16) & 0xFF;
    final green = (argb >>> 8) & 0xFF;
    final blue = argb & 0xFF;
    if (alpha == 0xFF) {
      final rgb = argb & 0x00FFFFFF;
      return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    }
    final opacity = (alpha / 255).toStringAsFixed(3);
    return 'rgba($red, $green, $blue, $opacity)';
  }

  void _neutralizeElement(html_dom.Element element) {
    _rewriteForeground(element, null);
    _rewriteBackground(element, null);
  }
}

final class _TraversalColorState {
  const _TraversalColorState({
    required this.resolved,
    required this.originalBackground,
    required this.concealed,
  });

  final ForumHtmlResolvedColorState resolved;
  final Color originalBackground;
  final bool concealed;
}

final class _MutableThemeAdaptationStats {
  int explicitForegroundCount = 0;
  int remappedForegroundCount = 0;
  int explicitBackgroundCount = 0;
  int remappedBackgroundCount = 0;
  int semanticFallbackCount = 0;
  int unsupportedColorCount = 0;
  int concealedTextRangeCount = 0;
  double? minimumResultContrast;

  void recordContrast(double value) {
    final current = minimumResultContrast;
    if (current == null || value < current) {
      minimumResultContrast = value;
    }
  }

  ForumHtmlThemeAdaptationStats build() {
    return ForumHtmlThemeAdaptationStats(
      explicitForegroundCount: explicitForegroundCount,
      remappedForegroundCount: remappedForegroundCount,
      explicitBackgroundCount: explicitBackgroundCount,
      remappedBackgroundCount: remappedBackgroundCount,
      semanticFallbackCount: semanticFallbackCount,
      unsupportedColorCount: unsupportedColorCount,
      concealedTextRangeCount: concealedTextRangeCount,
      minimumResultContrast: minimumResultContrast,
    );
  }
}
