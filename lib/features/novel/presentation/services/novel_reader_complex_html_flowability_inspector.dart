import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/presentation/services/novel_reader_protected_inline_node_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_inline_style_declarations.dart';

enum NovelReaderComplexHtmlFlowabilityFailure {
  noRenderableText,
  containsDedicatedContent,
  containsAtomicWidget,
  containsScriptedLayout,
  containsNonMonotonicStyle,
  invalidInlineStyle,
}

@immutable
final class NovelReaderComplexHtmlFlowability {
  const NovelReaderComplexHtmlFlowability({
    required this.isTextBearing,
    required this.isMonotonic,
    required this.hasProtectedInlineNodes,
    required this.requiresRubyBoundaries,
    required this.failure,
  });

  final bool isTextBearing;
  final bool isMonotonic;
  final bool hasProtectedInlineNodes;
  final bool requiresRubyBoundaries;
  final NovelReaderComplexHtmlFlowabilityFailure? failure;

  bool get isFlowable => isTextBearing && isMonotonic && failure == null;
}

abstract interface class NovelReaderComplexHtmlFlowabilityInspector {
  NovelReaderComplexHtmlFlowability inspect(String html);
}

final class DefaultNovelReaderComplexHtmlFlowabilityInspector
    implements NovelReaderComplexHtmlFlowabilityInspector {
  const DefaultNovelReaderComplexHtmlFlowabilityInspector({
    CssInlineStyleDeclarationCodec declarationCodec =
        const CssInlineStyleDeclarationCodec(),
    this.protectedInlineNodeAdapter =
        const DefaultNovelReaderProtectedInlineNodeAdapter(),
  }) : _declarationCodec = declarationCodec;

  final CssInlineStyleDeclarationCodec _declarationCodec;
  final NovelReaderProtectedInlineNodeAdapter protectedInlineNodeAdapter;

  static const _dedicatedSelector =
      'table,thead,tbody,tfoot,tr,td,th,.showcollapse_box';
  static const _scriptedSelector = 'script';
  static const _atomicSelector =
      'audio,canvas,details,embed,fieldset,iframe,object,pre,code,'
      'sub,sup,video';
  static const _nonMonotonicProperties = <String>{
    'position',
    'float',
    'display',
    'columns',
    'column-count',
    'column-width',
    'transform',
    'width',
    'height',
    'min-height',
    'max-height',
  };

  @override
  NovelReaderComplexHtmlFlowability inspect(String html) {
    final fragment = html_parser.parseFragment(html);
    final text = fragment.text ?? '';
    var hasStableProtectedInlineNodes = false;
    for (final element in fragment.querySelectorAll(
      'img,[data-y300-protected-inline]',
    )) {
      final assessment = protectedInlineNodeAdapter.assess(element);
      if (!assessment.isCandidate || !assessment.isStable) {
        return NovelReaderComplexHtmlFlowability(
          isTextBearing: _renderableTextPattern.hasMatch(text),
          isMonotonic: false,
          hasProtectedInlineNodes: hasStableProtectedInlineNodes,
          requiresRubyBoundaries: fragment.querySelector('ruby,rt,rp') != null,
          failure:
              NovelReaderComplexHtmlFlowabilityFailure.containsAtomicWidget,
        );
      }
      hasStableProtectedInlineNodes = true;
    }
    final isTextBearing =
        _renderableTextPattern.hasMatch(text) || hasStableProtectedInlineNodes;
    final requiresRubyBoundaries = fragment.querySelector('ruby,rt,rp') != null;
    final hasProtectedInlineNodes =
        requiresRubyBoundaries || hasStableProtectedInlineNodes;

    if (fragment.querySelector(_dedicatedSelector) != null) {
      return NovelReaderComplexHtmlFlowability(
        isTextBearing: isTextBearing,
        isMonotonic: false,
        hasProtectedInlineNodes: hasProtectedInlineNodes,
        requiresRubyBoundaries: requiresRubyBoundaries,
        failure:
            NovelReaderComplexHtmlFlowabilityFailure.containsDedicatedContent,
      );
    }
    if (fragment.querySelector(_scriptedSelector) != null) {
      return NovelReaderComplexHtmlFlowability(
        isTextBearing: isTextBearing,
        isMonotonic: false,
        hasProtectedInlineNodes: hasProtectedInlineNodes,
        requiresRubyBoundaries: requiresRubyBoundaries,
        failure:
            NovelReaderComplexHtmlFlowabilityFailure.containsScriptedLayout,
      );
    }
    if (fragment.querySelector(_atomicSelector) != null) {
      return NovelReaderComplexHtmlFlowability(
        isTextBearing: isTextBearing,
        isMonotonic: false,
        hasProtectedInlineNodes: hasProtectedInlineNodes,
        requiresRubyBoundaries: requiresRubyBoundaries,
        failure: NovelReaderComplexHtmlFlowabilityFailure.containsAtomicWidget,
      );
    }
    if (!isTextBearing) {
      return NovelReaderComplexHtmlFlowability(
        isTextBearing: false,
        isMonotonic: false,
        hasProtectedInlineNodes: hasProtectedInlineNodes,
        requiresRubyBoundaries: requiresRubyBoundaries,
        failure: NovelReaderComplexHtmlFlowabilityFailure.noRenderableText,
      );
    }

    for (final element in fragment.querySelectorAll('*')) {
      if (_hasEventAttribute(element)) {
        return NovelReaderComplexHtmlFlowability(
          isTextBearing: true,
          isMonotonic: false,
          hasProtectedInlineNodes: hasProtectedInlineNodes,
          requiresRubyBoundaries: requiresRubyBoundaries,
          failure:
              NovelReaderComplexHtmlFlowabilityFailure.containsScriptedLayout,
        );
      }
      final style = element.attributes['style'];
      if (style == null || style.trim().isEmpty) {
        continue;
      }
      final declarations = _declarationCodec.tryParse(style);
      if (declarations == null) {
        return NovelReaderComplexHtmlFlowability(
          isTextBearing: true,
          isMonotonic: false,
          hasProtectedInlineNodes: hasProtectedInlineNodes,
          requiresRubyBoundaries: requiresRubyBoundaries,
          failure: NovelReaderComplexHtmlFlowabilityFailure.invalidInlineStyle,
        );
      }
      if (declarations.declarations.any(
        (declaration) => _nonMonotonicProperties.contains(declaration.property),
      )) {
        return NovelReaderComplexHtmlFlowability(
          isTextBearing: true,
          isMonotonic: false,
          hasProtectedInlineNodes: hasProtectedInlineNodes,
          requiresRubyBoundaries: requiresRubyBoundaries,
          failure: NovelReaderComplexHtmlFlowabilityFailure
              .containsNonMonotonicStyle,
        );
      }
    }

    return NovelReaderComplexHtmlFlowability(
      isTextBearing: true,
      isMonotonic: true,
      hasProtectedInlineNodes: hasProtectedInlineNodes,
      requiresRubyBoundaries: requiresRubyBoundaries,
      failure: null,
    );
  }

  bool _hasEventAttribute(html_dom.Element element) {
    return element.attributes.keys.any(
      (name) => name.toString().toLowerCase().startsWith('on'),
    );
  }

  static final RegExp _renderableTextPattern = RegExp(
    r'[^\s\u00A0\u200B\u2060\u3000\uFEFF]',
  );
}
