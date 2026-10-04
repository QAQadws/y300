import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:y300/features/content_rendering_shared/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/content_rendering_shared/presentation/html_rendering/theme/forum_html_theme_context.dart';

abstract interface class ForumHtmlRenderPreparer {
  ForumHtmlPreparedRenderDocument prepare({
    required String html,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  });
}
