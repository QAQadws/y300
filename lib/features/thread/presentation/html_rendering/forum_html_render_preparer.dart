import 'package:html/dom.dart' as html_dom;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_fragment_codec.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_image_deduplicator.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_style_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_color_adaptation_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

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

class DefaultForumHtmlRenderPreparer implements ForumHtmlRenderPreparer {
  const DefaultForumHtmlRenderPreparer({
    ForumImageRequestResolver imageRequestResolver =
        const DefaultForumImageRequestResolver(),
    ForumHtmlImageDeduplicator imageDeduplicator =
        const ForumHtmlImageDeduplicator(),
    ForumHtmlFragmentCodec fragmentCodec =
        const HtmlPackageForumHtmlFragmentCodec(),
    ForumHtmlThemeAdapter themeAdapter = const DefaultForumHtmlThemeAdapter(),
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _imageRequestResolver = imageRequestResolver,
       _imageDeduplicator = imageDeduplicator,
       _fragmentCodec = fragmentCodec,
       _themeAdapter = themeAdapter,
       _urlResolver = urlResolver;

  final ForumImageRequestResolver _imageRequestResolver;
  final ForumHtmlImageDeduplicator _imageDeduplicator;
  final ForumHtmlFragmentCodec _fragmentCodec;
  final ForumHtmlThemeAdapter _themeAdapter;
  final SiteUrlResolver _urlResolver;

  @override
  ForumHtmlPreparedRenderDocument prepare({
    required String html,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) {
    final stylePolicy = ForumHtmlStylePolicy(preferences, theme: theme);
    final fragment = _fragmentCodec.parse(html);
    stylePolicy.normalizeStructure(fragment);
    stylePolicy.normalizeAuthorStyles(fragment);
    final themeAdaptationStats = _themeAdapter
        .adapt(
          fragment: fragment,
          theme: theme,
          policy: ForumHtmlColorAdaptationPolicy.standard,
        )
        .stats;
    _imageDeduplicator.deduplicateAttachmentImagesInFragment(fragment);
    final entries = <ForumHtmlReadableImageEntry>[];
    final attachmentIdsByUrl = <String, String>{};
    final readableUrlCounts = <String, int>{};
    final images = fragment.querySelectorAll('img');
    var skippedStickerCount = 0;
    var skippedNonNetworkCount = 0;
    var attachmentTaggedCount = 0;

    for (final image in images) {
      final rawSrc = _rawImageSourceFromElement(image);
      if (rawSrc == null || rawSrc.isEmpty) {
        skippedNonNetworkCount++;
        continue;
      }
      final normalizedSrc =
          DefaultForumImageSourcePipeline.normalizeImageSource(
            rawSrc,
            urlResolver: _urlResolver.resolve,
          );
      final resolved = normalizedSrc == null
          ? null
          : Uri.tryParse(normalizedSrc);
      if (resolved == null || !_isHttpUri(resolved)) {
        skippedNonNetworkCount++;
        continue;
      }
      final resolvedSrc = normalizedSrc;
      if (resolvedSrc == null) {
        skippedNonNetworkCount++;
        continue;
      }
      image.attributes['src'] = resolvedSrc;

      final attachmentId = _attachmentIdFromElement(image);
      if (attachmentId != null) {
        attachmentTaggedCount++;
        _recordAttachmentId(attachmentIdsByUrl, rawSrc, resolved, attachmentId);
      }

      final resolvedUrl = resolved.toString();
      if (_isForumStickerImage(resolvedUrl)) {
        skippedStickerCount++;
        continue;
      }

      final index = entries.length;
      final htmlWidth = _parsePositiveDouble(image.attributes['width']);
      final htmlHeight = _parsePositiveDouble(image.attributes['height']);
      final spec = ForumImageLoadSpec(
        kind: ForumImageKind.threadInline,
        url: resolved,
        ownerId: _ownerId(
          threadId: threadId,
          imageCacheOwnerId: imageCacheOwnerId,
        ),
        ownerType: ImageCacheOwnerType.thread,
        imageIndex: index,
        htmlWidth: htmlWidth,
        htmlHeight: htmlHeight,
        alt: image.attributes['alt'],
        title: image.attributes['title'],
        allowReaderOpen: true,
      );
      final request = _imageRequestResolver.resolveCacheRequest(spec);
      if (request == null) {
        skippedNonNetworkCount++;
        continue;
      }

      image.attributes[forumHtmlReadableImageIndexAttribute] = index.toString();
      final normalizedUrl = resolved.removeFragment().toString();
      readableUrlCounts[normalizedUrl] =
          (readableUrlCounts[normalizedUrl] ?? 0) + 1;
      entries.add(
        ForumHtmlReadableImageEntry(
          index: index,
          url: resolvedUrl,
          rawSrc: rawSrc,
          cacheKey: request.cacheKey,
          spec: ForumImageLoadSpec(
            kind: spec.kind,
            url: spec.url,
            ownerId: spec.ownerId,
            ownerType: spec.ownerType,
            imageIndex: spec.imageIndex,
            cacheKey: request.cacheKey,
            retentionClass: request.retentionClass,
            htmlWidth: spec.htmlWidth,
            htmlHeight: spec.htmlHeight,
            alt: spec.alt,
            title: spec.title,
            allowReaderOpen: true,
          ),
          attachmentId: attachmentId,
          alt: image.attributes['alt'],
          title: image.attributes['title'],
          htmlWidth: htmlWidth,
          htmlHeight: htmlHeight,
        ),
      );
    }

    return ForumHtmlPreparedRenderDocument(
      preparedHtml: _fragmentCodec.serialize(fragment),
      sequence: ForumHtmlReadableImageSequence(
        sourceId: sourceId,
        entries: List<ForumHtmlReadableImageEntry>.unmodifiable(entries),
      ),
      attachmentIdsByUrl: Map<String, String>.unmodifiable(attachmentIdsByUrl),
      totalImageCount: images.length,
      skippedStickerCount: skippedStickerCount,
      skippedNonNetworkCount: skippedNonNetworkCount,
      duplicatedReadableUrlCount: _duplicateCount(readableUrlCounts),
      attachmentTaggedCount: attachmentTaggedCount,
      themeSignature: theme.signature,
      themeAdaptationStats: themeAdaptationStats,
    );
  }

  int _duplicateCount(Map<String, int> counts) {
    var duplicates = 0;
    for (final count in counts.values) {
      if (count > 1) {
        duplicates += count - 1;
      }
    }
    return duplicates;
  }

  String _ownerId({
    required String? threadId,
    required String? imageCacheOwnerId,
  }) {
    final owner = imageCacheOwnerId?.trim();
    if (owner != null && owner.isNotEmpty) {
      return owner;
    }
    final tid = threadId?.trim();
    return tid == null || tid.isEmpty ? 'unknown' : tid;
  }

  void _recordAttachmentId(
    Map<String, String> result,
    String rawSrc,
    Uri resolved,
    String attachmentId,
  ) {
    result[rawSrc] = attachmentId;
    result[resolved.toString()] = attachmentId;
    result[resolved.removeFragment().toString()] = attachmentId;
  }

  String? _rawImageSourceFromElement(html_dom.Element element) {
    return DefaultForumImageSourcePipeline.firstDomImageSourceFromElement(
      element,
      domAttributes: const <String>[
        'zoomfile',
        'file',
        'data-original',
        'data-src',
        'src',
      ],
    );
  }

  String? _attachmentIdFromElement(html_dom.Element element) {
    final id = element.id;
    final aimgMatch = RegExp(r'^aimg_(\d+)$').firstMatch(id);
    if (aimgMatch != null) {
      return aimgMatch.group(1);
    }
    final aid = element.attributes['aid']?.trim();
    if (aid != null && aid.isNotEmpty) {
      return aid;
    }
    final src = _rawImageSourceFromElement(element);
    return src == null ? null : _attachmentIdFromUrl(src);
  }

  String? _attachmentIdFromUrl(String url) {
    final aimgMatch = RegExp(r'aimg[_=/-](\d+)').firstMatch(url);
    if (aimgMatch != null) {
      return aimgMatch.group(1);
    }
    final aidMatch = RegExp(r'(?:aid|attachmentid)=(\d+)').firstMatch(url);
    return aidMatch?.group(1);
  }

  double? _parsePositiveDouble(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  bool _isHttpUri(Uri uri) {
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  bool _isForumStickerImage(String url) {
    return url.contains('/static/image/smiley/') ||
        url.contains('static/image/smiley/');
  }
}
