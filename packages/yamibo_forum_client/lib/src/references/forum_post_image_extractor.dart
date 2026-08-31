import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../contracts/thread_detail_models.dart';
import '../url/forum_uri_resolver.dart';

/// Values describing forum image source origin.
enum ForumImageSourceOrigin {
  /// Image discovered from post-body DOM markup.
  dom,

  /// Image projected from structured attachment metadata.
  attachment,
}

/// Values describing forum image host kind.
enum ForumImageHostKind {
  /// Yamibo attachment.
  yamiboAttachment,

  /// Yamibo static.
  yamiboStatic,

  /// Third party.
  thirdParty,

  /// Unknown.
  unknown,
}

/// Source-neutral forum image source.
final class ForumImageSource {
  /// Creates a [ForumImageSource].
  const ForumImageSource({
    required this.rawUrl,
    required this.normalizedUrl,
    required this.origin,
    required this.hostKind,
    required this.position,
    this.aid,
  });

  /// Raw url.
  final String rawUrl;

  /// Normalized url.
  final String normalizedUrl;

  /// Origin reported for this value.
  final ForumImageSourceOrigin origin;

  /// Host kind.
  final ForumImageHostKind hostKind;

  /// Position.
  final int position;

  /// Stable attachment identifier.
  final String? aid;

  /// Stable attachment identifier, when this source came from an attachment.
  String? get attachmentId => aid;
}

/// Source-neutral forum image source options.
final class ForumImageSourceOptions {
  /// Default dom attributes.
  static const List<String> defaultDomAttributes = <String>[
    'src',
    'data-src',
    'data-original',
    'file',
  ];

  /// Creates a [ForumImageSourceOptions].
  const ForumImageSourceOptions({
    this.includeForumChrome = false,
    this.includeAttachments = true,
    this.domAttributes = defaultDomAttributes,
  });

  /// Include forum chrome.
  final bool includeForumChrome;

  /// Include attachments.
  final bool includeAttachments;

  /// Dom attributes.
  final List<String> domAttributes;
}

/// Resolves one raw image reference to a normalized URL.
typedef ForumImageUrlResolver = String? Function(String rawUrl);

/// Source-neutral forum image source pipeline.
abstract interface class ForumImageSourcePipeline {
  /// Collects normalized post images in stable display order.
  List<ForumImageSource> collectFromPost(
    ThreadPost post, {
    ForumImageSourceOptions options = const ForumImageSourceOptions(),
  });
}

/// Canonical DOM-first image projection shared by package adapters and Y300.
final class DefaultForumImageSourcePipeline
    implements ForumImageSourcePipeline {
  /// Creates a [DefaultForumImageSourcePipeline].
  const DefaultForumImageSourcePipeline({
    this.urlResolver,
    this.siteBaseUrl = 'https://bbs.yamibo.com',
  });

  /// Url resolver.
  final ForumImageUrlResolver? urlResolver;

  /// Site base url.
  final String siteBaseUrl;

  /// Pattern used to exclude forum chrome images from post content.
  static final RegExp forumChromeImagePattern = RegExp(
    r'(smilies|static/image|emotion|avatar|uc_server/data/avatar)',
    caseSensitive: false,
  );

  @override
  List<ForumImageSource> collectFromPost(
    ThreadPost post, {
    ForumImageSourceOptions options = const ForumImageSourceOptions(),
  }) {
    final sources = <ForumImageSource>[];
    final seen = <String>{};
    for (final source in collectDomImageSources(
      post.message,
      urlResolver: urlResolver,
      includeForumChrome: options.includeForumChrome,
      domAttributes: options.domAttributes,
      siteBaseUrl: siteBaseUrl,
    )) {
      if (seen.add(source.normalizedUrl)) sources.add(source);
    }
    if (!options.includeAttachments) return sources;
    for (final source in extractAttachmentSources(
      post,
      urlResolver: urlResolver,
      siteBaseUrl: siteBaseUrl,
    )) {
      if (seen.add(source.normalizedUrl)) sources.add(source);
    }
    return List<ForumImageSource>.unmodifiable(sources);
  }

  /// Collects normalized image elements from HTML in DOM order.
  static List<ForumImageSource> collectDomImageSources(
    String html, {
    ForumImageUrlResolver? urlResolver,
    bool includeForumChrome = false,
    List<String> domAttributes = ForumImageSourceOptions.defaultDomAttributes,
    String siteBaseUrl = 'https://bbs.yamibo.com',
  }) {
    final sources = <ForumImageSource>[];
    final seen = <String>{};
    var position = 0;
    for (final node
        in html_parser.parseFragment(html).querySelectorAll('img')) {
      final rawUrl = firstDomImageSourceFromElement(
        node,
        domAttributes: domAttributes,
      );
      if (rawUrl == null) continue;
      final normalizedUrl = normalizeImageSource(
        rawUrl,
        urlResolver: urlResolver,
        siteBaseUrl: siteBaseUrl,
      );
      if (normalizedUrl == null ||
          !isHttpImageUrl(normalizedUrl) ||
          (!includeForumChrome && isForumChromeImage(normalizedUrl)) ||
          !seen.add(normalizedUrl)) {
        continue;
      }
      sources.add(
        ForumImageSource(
          rawUrl: rawUrl,
          normalizedUrl: normalizedUrl,
          origin: ForumImageSourceOrigin.dom,
          hostKind: classifyHostKind(normalizedUrl, siteBaseUrl: siteBaseUrl),
          position: position++,
        ),
      );
    }
    return sources;
  }

  /// Projects structured attachment images in source order.
  static List<ForumImageSource> extractAttachmentSources(
    ThreadPost post, {
    ForumImageUrlResolver? urlResolver,
    String siteBaseUrl = 'https://bbs.yamibo.com',
  }) {
    final sources = <ForumImageSource>[];
    final seen = <String>{};
    var position = 0;
    for (final attachment in post.attachmentImages) {
      if (!isImageAttachment(attachment)) continue;
      final rawUrl = joinAttachmentUrl(attachment.url, attachment.attachment);
      final normalizedUrl = normalizeImageSource(
        rawUrl,
        urlResolver: urlResolver,
        siteBaseUrl: siteBaseUrl,
      );
      if (normalizedUrl == null ||
          !isHttpImageUrl(normalizedUrl) ||
          !seen.add(normalizedUrl)) {
        continue;
      }
      sources.add(
        ForumImageSource(
          rawUrl: rawUrl,
          normalizedUrl: normalizedUrl,
          origin: ForumImageSourceOrigin.attachment,
          hostKind: classifyHostKind(normalizedUrl, siteBaseUrl: siteBaseUrl),
          position: position++,
          aid: attachment.aid.trim().isEmpty ? null : attachment.aid.trim(),
        ),
      );
    }
    return sources;
  }

  /// Resolves and normalizes one raw image source.
  static String? normalizeImageSource(
    String rawUrl, {
    ForumImageUrlResolver? urlResolver,
    String siteBaseUrl = 'https://bbs.yamibo.com',
  }) {
    if (urlResolver != null) return urlResolver(rawUrl);
    try {
      return ForumUriResolver(
        siteOrigin: Uri.parse(siteBaseUrl),
      ).resolve(rawUrl).toString();
    } on FormatException {
      return null;
    }
  }

  /// Returns the first configured non-empty source attribute on [node].
  static String? firstDomImageSourceFromElement(
    html_dom.Element node, {
    List<String> domAttributes = ForumImageSourceOptions.defaultDomAttributes,
  }) {
    for (final attribute in domAttributes) {
      final value = node.attributes[attribute]?.trim();
      if (value?.isNotEmpty == true) return value;
    }
    return null;
  }

  /// Whether a normalized URL points to known forum chrome media.
  static bool isForumChromeImage(String normalizedUrl) =>
      forumChromeImagePattern.hasMatch(normalizedUrl);

  /// Whether attachment metadata proves an image payload.
  static bool isImageAttachment(ForumPostAttachmentImage attachment) {
    if (attachment.attachimg.trim() == '1') return true;
    final extension = attachment.ext.trim().toLowerCase();
    if (_imageExtensions.contains(extension)) return true;
    final pathExtension = extensionFromPath(attachment.attachment);
    return pathExtension != null && _imageExtensions.contains(pathExtension);
  }

  /// Joins split Discuz attachment URL components safely.
  static String joinAttachmentUrl(String base, String attachment) {
    final normalizedBase = base.trim();
    final normalizedAttachment = attachment.trim();
    if (normalizedAttachment.startsWith('http://') ||
        normalizedAttachment.startsWith('https://') ||
        normalizedAttachment.startsWith('//') ||
        normalizedAttachment.startsWith('/')) {
      return normalizedAttachment;
    }
    if (normalizedBase.isEmpty) return normalizedAttachment;
    return normalizedBase.endsWith('/')
        ? '$normalizedBase$normalizedAttachment'
        : '$normalizedBase/$normalizedAttachment';
  }

  /// Extracts a lower-case file extension from a URL path.
  static String? extensionFromPath(String path) {
    final cleanPath = path.split('?').first.split('#').first.trim();
    final dot = cleanPath.lastIndexOf('.');
    if (dot < 0 || dot == cleanPath.length - 1) return null;
    return cleanPath.substring(dot + 1).toLowerCase();
  }

  /// Whether the value is an absolute HTTP or HTTPS URL.
  static bool isHttpImageUrl(String normalizedUrl) {
    final uri = Uri.tryParse(normalizedUrl);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Classifies a normalized image URL by its relationship to the forum.
  static ForumImageHostKind classifyHostKind(
    String normalizedUrl, {
    String siteBaseUrl = 'https://bbs.yamibo.com',
  }) {
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return ForumImageHostKind.unknown;
    }
    final siteHost = Uri.tryParse(siteBaseUrl)?.host.toLowerCase() ?? '';
    final host = uri.host.toLowerCase();
    if (siteHost.isNotEmpty && host == siteHost) {
      return uri.path.toLowerCase().startsWith('/data/attachment/')
          ? ForumImageHostKind.yamiboAttachment
          : ForumImageHostKind.yamiboStatic;
    }
    return host.isEmpty
        ? ForumImageHostKind.unknown
        : ForumImageHostKind.thirdParty;
  }

  static const Set<String> _imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
  };
}
