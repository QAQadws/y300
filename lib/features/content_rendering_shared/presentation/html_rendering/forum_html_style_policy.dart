import '../../application/forum_html_render_preferences_projection.dart';

import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';

export 'package:forum_content_renderer/forum_content_renderer.dart'
    show ForumHtmlBlockSpacingMode;

/// App compatibility entry point for preference-based rendering.
class ForumHtmlStylePolicy extends ForumHtmlRenderStylePolicy {
  ForumHtmlStylePolicy(
    this.preferences, {
    required super.theme,
    super.blockSpacingMode = ForumHtmlBlockSpacingMode.paragraphLikeDivs,
    super.contentLayout = ForumHtmlContentLayout.document,
    super.inlineStyleDeclarationCodec = const CssInlineStyleDeclarationCodec(),
  }) : super(preferences.renderOptions);

  final ForumHtmlReaderPreferences preferences;
}
