import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/content_rendering_shared/application/host/forum_cache_html_preparation_image_policy.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/content_rendering_shared/presentation/contracts/forum_html_render_preparer.dart';
import 'forum_html_render_preferences_projection.dart';

/// Unknown preparers may consume every preference, including conversion mode.
extension ForumHtmlPreparationPreferencesIdentity on ForumHtmlRenderPreparer {
  Object preparationPreferencesIdentity(
    ForumHtmlReaderPreferences preferences,
  ) {
    // A subclass can override prepare and introduce additional dependencies.
    // Only the exact default facade has this verified preparation projection.
    return runtimeType == DefaultForumHtmlRenderPreparer
        ? preferences.preserveAuthorFontSize
        : preferences;
  }
}

/// App defaults stay as values so this facade can cross preparation isolates.
class DefaultForumHtmlRenderPreparer implements ForumHtmlRenderPreparer {
  /// [imageRequestResolver] configures the default cache policy. An injected
  /// [imagePolicy] resolves its own resources.
  const DefaultForumHtmlRenderPreparer({
    ForumImageRequestResolver imageRequestResolver =
        const DefaultForumImageRequestResolver(),
    ForumHtmlImageDeduplicator? imageDeduplicator,
    ForumHtmlFragmentCodec fragmentCodec =
        const HtmlPackageForumHtmlFragmentCodec(),
    ForumHtmlThemeAdapter themeAdapter = const DefaultForumHtmlThemeAdapter(),
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
    ForumHtmlPreparationImagePolicy? imagePolicy,
    this.enablePlainTextLinks = false,
  }) : _imageRequestResolver = imageRequestResolver,
       _imageDeduplicator = imageDeduplicator,
       _fragmentCodec = fragmentCodec,
       _themeAdapter = themeAdapter,
       _urlResolver = urlResolver,
       _imagePolicy = imagePolicy;

  final ForumImageRequestResolver _imageRequestResolver;
  final ForumHtmlImageDeduplicator? _imageDeduplicator;
  final ForumHtmlFragmentCodec _fragmentCodec;
  final ForumHtmlThemeAdapter _themeAdapter;
  final SiteUrlResolver _urlResolver;
  final ForumHtmlPreparationImagePolicy? _imagePolicy;

  /// Display-only capability; it is not a persisted reading preference.
  final bool enablePlainTextLinks;

  @override
  ForumHtmlPreparedRenderDocument prepare({
    required String html,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) =>
      ForumHtmlPreparationPipeline(
        imagePolicy:
            _imagePolicy ??
            ForumCacheHtmlPreparationImagePolicy(
              imageRequestResolver: _imageRequestResolver,
            ),
        // The legacy default deduplicator has its own site resolver, even when
        // callers customize the resolver used for document image preparation.
        imageDeduplicator:
            _imageDeduplicator ??
            ForumHtmlImageDeduplicator(
              resolveUrl: const SiteUrlResolver().resolve,
            ),
        fragmentCodec: _fragmentCodec,
        themeAdapter: _themeAdapter,
        resolveUrl: _urlResolver.resolve,
      ).prepare(
        html: html,
        options: preferences.renderOptions.copyWith(
          enablePlainTextLinks: enablePlainTextLinks,
        ),
        theme: theme,
        sourceId: sourceId,
        threadId: threadId,
        imageCacheOwnerId: imageCacheOwnerId,
      );
}
