import '../../application/forum_html_render_preferences_projection.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/content_rendering_shared/presentation/contracts/forum_html_render_preparer.dart';

/// App compatibility entry point for preference-based preparation.
class ForumHtmlRenderPipeline implements ForumHtmlRenderPreparer {
  const ForumHtmlRenderPipeline({
    required ForumHtmlPreparationImagePolicy imagePolicy,
    required String? Function(String) resolveUrl,
    ForumHtmlImageDeduplicator? imageDeduplicator,
    ForumHtmlFragmentCodec fragmentCodec =
        const HtmlPackageForumHtmlFragmentCodec(),
    ForumHtmlThemeAdapter themeAdapter = const DefaultForumHtmlThemeAdapter(),
  }) : _imageDeduplicator = imageDeduplicator,
       _fragmentCodec = fragmentCodec,
       _themeAdapter = themeAdapter,
       _resolveUrl = resolveUrl,
       _imagePolicy = imagePolicy;

  final ForumHtmlImageDeduplicator? _imageDeduplicator;
  final ForumHtmlFragmentCodec _fragmentCodec;
  final ForumHtmlThemeAdapter _themeAdapter;
  final String? Function(String) _resolveUrl;
  final ForumHtmlPreparationImagePolicy _imagePolicy;

  @override
  ForumHtmlPreparedRenderDocument prepare({
    required String html,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) {
    return ForumHtmlPreparationPipeline(
      imagePolicy: _imagePolicy,
      resolveUrl: _resolveUrl,
      imageDeduplicator: _imageDeduplicator,
      fragmentCodec: _fragmentCodec,
      themeAdapter: _themeAdapter,
    ).prepare(
      html: html,
      options: preferences.renderOptions,
      theme: theme,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
    );
  }
}
