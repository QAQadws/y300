import '../../application/forum_html_render_preferences_projection.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

export 'package:forum_content_renderer/forum_content_renderer.dart'
    show ForumHtmlResolvedTextStyle, ForumHtmlTextStyleResolutionFailure;

/// App compatibility port for preference-based fast layout.
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

  @override
  ForumHtmlResolvedTextStyle resolve({
    required html_dom.Element element,
    required TextStyle parentStyle,
    required TextStyle baseStyle,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
  }) {
    return DefaultForumHtmlRenderTextStyleResolver(
      declarationCodec: _declarationCodec,
      colorParser: _colorParser,
    ).resolve(
      element: element,
      parentStyle: parentStyle,
      baseStyle: baseStyle,
      options: preferences.renderOptions,
      theme: theme,
    );
  }
}
