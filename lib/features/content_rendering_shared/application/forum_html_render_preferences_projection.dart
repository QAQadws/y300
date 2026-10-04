import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../domain/models/forum_html_reader_preferences.dart';

/// Host conversion/persistence identity never enters the renderer's options.
extension ForumHtmlRenderPreferencesProjection on ForumHtmlReaderPreferences {
  ForumHtmlRenderOptions get renderOptions => ForumHtmlRenderOptions(
    fontScale: typography.fontScale,
    lineHeightScale: typography.lineHeightScale,
    paragraphSpacing: typography.paragraphSpacing,
    preserveAuthorFontSize: preserveAuthorFontSize,
  );
}
