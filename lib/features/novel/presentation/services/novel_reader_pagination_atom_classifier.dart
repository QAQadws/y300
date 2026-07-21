import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_text_style_resolver.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_inline_style_declarations.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

final class NovelReaderPaginationAtomClassifier {
  const NovelReaderPaginationAtomClassifier({
    this.styleResolver = const DefaultForumHtmlTextStyleResolver(),
    CssInlineStyleDeclarationCodec declarationCodec =
        const CssInlineStyleDeclarationCodec(),
  }) : _declarationCodec = declarationCodec;

  final ForumHtmlTextStyleResolver styleResolver;
  final CssInlineStyleDeclarationCodec _declarationCodec;

  static const Set<String> _rootBlockTags = <String>{
    'p',
    'div',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  };

  static const Set<String> _inlineTags = <String>{
    'a',
    'b',
    'br',
    'em',
    'font',
    'i',
    'mark',
    'small',
    'span',
    'strong',
    'u',
  };

  static const Set<String> _supportedStyleProperties = <String>{
    'background',
    'background-color',
    'color',
    'font-family',
    'font-size',
    'font-style',
    'font-weight',
  };

  NovelReaderClassifiedPaginationAtom classify({
    required NovelReaderPaginationAtom atom,
    required TextStyle baseStyle,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
  }) {
    if (atom.isIsolatedImage) {
      return _classified(
        atom,
        NovelReaderPaginationRoute.isolatedImage,
        NovelReaderPaginationRouteReason.isolatedReadableImage,
      );
    }
    final fragment = html_parser.parseFragment(atom.html);
    if (_contains(fragment, 'ruby,rt,rp')) {
      return _classified(
        atom,
        NovelReaderPaginationRoute.rubyInline,
        NovelReaderPaginationRouteReason.containsRuby,
      );
    }
    if (_contains(fragment, '.showcollapse_box')) {
      return _classified(
        atom,
        NovelReaderPaginationRoute.collapseBlock,
        NovelReaderPaginationRouteReason.containsCollapse,
      );
    }
    if (_contains(fragment, 'table,thead,tbody,tfoot,tr,td,th')) {
      return _classified(
        atom,
        NovelReaderPaginationRoute.tableBlock,
        NovelReaderPaginationRouteReason.containsTable,
      );
    }
    if (_contains(fragment, 'img')) {
      return _classified(
        atom,
        NovelReaderPaginationRoute.complexHtml,
        NovelReaderPaginationRouteReason.containsImage,
      );
    }
    if (_contains(
      fragment,
      'audio,canvas,details,embed,fieldset,iframe,object,pre,code,sub,sup,video',
    )) {
      return _classified(
        atom,
        NovelReaderPaginationRoute.complexHtml,
        NovelReaderPaginationRouteReason.containsWidgetSpan,
      );
    }
    if (atom.kind == NovelReaderPaginationAtomKind.atomicWidget) {
      return _classified(
        atom,
        NovelReaderPaginationRoute.complexHtml,
        NovelReaderPaginationRouteReason.atomicWidget,
      );
    }

    final roots = fragment.nodes.where(_isMeaningful).toList(growable: false);
    if (roots.length != 1) {
      return _classified(
        atom,
        NovelReaderPaginationRoute.complexHtml,
        NovelReaderPaginationRouteReason.unsupportedTag,
      );
    }
    final root = roots.single;
    final failure = _validateNode(
      root,
      isRoot: true,
      parentStyle: baseStyle,
      baseStyle: baseStyle,
      preferences: preferences,
      theme: theme,
    );
    if (failure != null) {
      return _classified(atom, NovelReaderPaginationRoute.complexHtml, failure);
    }
    return NovelReaderClassifiedPaginationAtom(
      atom: atom,
      route: NovelReaderPaginationRoute.safeText,
      isBreakable: true,
      reason: NovelReaderPaginationRouteReason.safeTextSubset,
    );
  }

  NovelReaderPaginationRouteReason? _validateNode(
    html_dom.Node node, {
    required bool isRoot,
    required TextStyle parentStyle,
    required TextStyle baseStyle,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
  }) {
    if (node is html_dom.Text) {
      return null;
    }
    if (node is! html_dom.Element) {
      return NovelReaderPaginationRouteReason.unsupportedTag;
    }
    final tag = node.localName?.toLowerCase() ?? '';
    if (isRoot ? !_rootBlockTags.contains(tag) : !_inlineTags.contains(tag)) {
      return NovelReaderPaginationRouteReason.unsupportedTag;
    }
    if (!isRoot && _rootBlockTags.contains(tag)) {
      return NovelReaderPaginationRouteReason.unsupportedTag;
    }
    final attributeFailure = _validateAttributes(node, isRoot: isRoot);
    if (attributeFailure != null) {
      return attributeFailure;
    }
    final resolved = styleResolver.resolve(
      element: node,
      parentStyle: parentStyle,
      baseStyle: baseStyle,
      preferences: preferences,
      theme: theme,
    );
    if (!resolved.isSupported) {
      return resolved.failure ==
              ForumHtmlTextStyleResolutionFailure.unsupportedFontFamily
          ? NovelReaderPaginationRouteReason.unsupportedFont
          : NovelReaderPaginationRouteReason.unsupportedStyle;
    }
    for (final child in node.nodes) {
      final failure = _validateNode(
        child,
        isRoot: false,
        parentStyle: resolved.style,
        baseStyle: baseStyle,
        preferences: preferences,
        theme: theme,
      );
      if (failure != null) {
        return failure;
      }
    }
    return null;
  }

  NovelReaderPaginationRouteReason? _validateAttributes(
    html_dom.Element element, {
    required bool isRoot,
  }) {
    for (final name in element.attributes.keys) {
      final normalized = name.toString().toLowerCase();
      if (normalized.startsWith('on')) {
        return NovelReaderPaginationRouteReason.unsupportedAttribute;
      }
      final allowed = switch (element.localName?.toLowerCase()) {
        'a' => const <String>{'href', 'target', 'rel', 'style'},
        'font' => const <String>{'color', 'face', 'size', 'style'},
        _ => const <String>{'style'},
      };
      if (!allowed.contains(normalized)) {
        return NovelReaderPaginationRouteReason.unsupportedAttribute;
      }
    }
    final style = element.attributes['style'];
    if (style == null || style.trim().isEmpty) {
      return null;
    }
    final parsed = _declarationCodec.tryParse(style);
    if (parsed == null ||
        parsed.declarations.any(
          (declaration) =>
              !_supportedStyleProperties.contains(declaration.property),
        )) {
      return NovelReaderPaginationRouteReason.unsupportedStyle;
    }
    if (isRoot &&
        parsed.declarations.any(
          (declaration) =>
              declaration.property == 'background' ||
              declaration.property == 'background-color',
        )) {
      return NovelReaderPaginationRouteReason.unsupportedStyle;
    }
    return null;
  }

  bool _contains(html_dom.DocumentFragment fragment, String selector) {
    return fragment.querySelector(selector) != null;
  }

  bool _isMeaningful(html_dom.Node node) {
    return node is! html_dom.Text || node.data.trim().isNotEmpty;
  }

  NovelReaderClassifiedPaginationAtom _classified(
    NovelReaderPaginationAtom atom,
    NovelReaderPaginationRoute route,
    NovelReaderPaginationRouteReason reason,
  ) {
    return NovelReaderClassifiedPaginationAtom(
      atom: atom,
      route: route,
      isBreakable: false,
      reason: reason,
    );
  }
}
