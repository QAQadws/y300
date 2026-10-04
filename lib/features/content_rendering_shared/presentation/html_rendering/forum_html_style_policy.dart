import '../../application/forum_html_render_preferences_projection.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';

export 'package:forum_content_renderer/forum_content_renderer.dart'
    show ForumHtmlBlockSpacingMode;

/// App compatibility entry point for preference-based rendering.
class ForumHtmlStylePolicy extends ForumHtmlRenderStylePolicy {
  ForumHtmlStylePolicy(
    this.preferences, {
    required ForumHtmlThemeContext theme,
    ForumHtmlBlockSpacingMode blockSpacingMode =
        ForumHtmlBlockSpacingMode.paragraphLikeDivs,
    ForumHtmlContentLayout contentLayout = ForumHtmlContentLayout.document,
    CssInlineStyleDeclarationCodec inlineStyleDeclarationCodec =
        const CssInlineStyleDeclarationCodec(),
  }) : super(
         preferences.renderOptions,
         theme: theme,
         blockSpacingMode: blockSpacingMode,
         contentLayout: contentLayout,
         inlineStyleDeclarationCodec: inlineStyleDeclarationCodec,
       );

  final ForumHtmlReaderPreferences preferences;
}
