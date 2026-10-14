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
    this.enableSafeDisplayPlanning = false,
    this.safeDisplayPlanningCodeUnitBudget,
  }) : _imageRequestResolver = imageRequestResolver,
       _imageDeduplicator = imageDeduplicator,
       _fragmentCodec = fragmentCodec,
       _themeAdapter = themeAdapter,
       _urlResolver = urlResolver,
       _imagePolicy = imagePolicy,
       assert(
         safeDisplayPlanningCodeUnitBudget == null ||
             safeDisplayPlanningCodeUnitBudget >= 0,
       );

  final ForumImageRequestResolver _imageRequestResolver;
  final ForumHtmlImageDeduplicator? _imageDeduplicator;
  final ForumHtmlFragmentCodec _fragmentCodec;
  final ForumHtmlThemeAdapter _themeAdapter;
  final SiteUrlResolver _urlResolver;
  final ForumHtmlPreparationImagePolicy? _imagePolicy;

  /// Display-only capability; it is not a persisted reading preference.
  final bool enablePlainTextLinks;

  /// Optional pure display plan, built alongside preparation in its worker.
  final bool enableSafeDisplayPlanning;

  /// A request-fixed retained-value allowance; null preserves existing callers.
  /// The full prepared HTML is a known lower bound before any plan is built.
  final int? safeDisplayPlanningCodeUnitBudget;

  /// Unknown injections can retain services or change preparation semantics.
  /// Workers reconstruct this verified default configuration from pure values.
  bool get supportsBackgroundPreparation =>
      runtimeType == DefaultForumHtmlRenderPreparer &&
      identical(
        _imageRequestResolver,
        const DefaultForumImageRequestResolver(),
      ) &&
      _imageDeduplicator == null &&
      identical(_fragmentCodec, const HtmlPackageForumHtmlFragmentCodec()) &&
      identical(_themeAdapter, const DefaultForumHtmlThemeAdapter()) &&
      identical(_urlResolver, const SiteUrlResolver()) &&
      _imagePolicy == null;

  @override
  ForumHtmlPreparedRenderDocument prepare({
    required String html,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) {
    final document =
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
    return enableSafeDisplayPlanning &&
            document.preparedHtml.length >= 32 * 1024 &&
            (safeDisplayPlanningCodeUnitBudget == null ||
                document.preparedHtml.length <
                    safeDisplayPlanningCodeUnitBudget!)
        ? document.copyWith(
            safeDisplayPlan: const ForumHtmlSafeDisplayPlanner(
              targetChunkUnits: 48,
            ).plan(document),
          )
        : document;
  }
}
