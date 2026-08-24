import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../contracts/thread_detail_models.dart';
import '../url/forum_uri_resolver.dart';

enum ForumImageSourceOrigin { dom, attachment }

enum ForumImageHostKind { yamiboAttachment, yamiboStatic, thirdParty, unknown }

final class ForumImageSource {
  const ForumImageSource({
    required this.rawUrl,
    required this.normalizedUrl,
    required this.origin,
    required this.hostKind,
    required this.position,
    this.aid,
  });

  final String rawUrl;
  final String normalizedUrl;
  final ForumImageSourceOrigin origin;
  final ForumImageHostKind hostKind;
  final int position;
  final String? aid;

  String? get attachmentId => aid;
}

final class ForumImageSourceOptions {
  static const List<String> defaultDomAttributes = <String>[
    'src',
    'data-src',
    'data-original',
    'file',
  ];

  const ForumImageSourceOptions({
    this.includeForumChrome = false,
    this.includeAttachments = true,
    this.domAttributes = defaultDomAttributes,
  });

  final bool includeForumChrome;
  final bool includeAttachments;
  final List<String> domAttributes;
}

typedef ForumImageUrlResolver = String? Function(String rawUrl);

abstract interface class ForumImageSourcePipeline {
  List<ForumImageSource> collectFromPost(
    ThreadPost post, {
    ForumImageSourceOptions options = const ForumImageSourceOptions(),
  });
}

/// Canonical DOM-first image projection shared by package adapters and Y300.
final class DefaultForumImageSourcePipeline
    implements ForumImageSourcePipeline {
  const DefaultForumImageSourcePipeline({
    this.urlResolver,
    this.siteBaseUrl = 'https://bbs.yamibo.com',
  });

  final ForumImageUrlResolver? urlResolver;
  final String siteBaseUrl;

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
    for (final node in html_parser.parseFragment(html).querySelectorAll('img')) {
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

  static String? normalizeImageSource(
    String rawUrl, {
    ForumImageUrlResolver? urlResolver,
    String siteBaseUrl = 'https://bbs.yamibo.com',
  }) {
    if (urlResolver != null) return urlResolver(rawUrl);
    try {
      return ForumUriResolver(siteOrigin: Uri.parse(siteBaseUrl))
          .resolve(rawUrl)
          .toString();
    } on FormatException {
      return null;
    }
  }

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

  static bool isForumChromeImage(String normalizedUrl) =>
      forumChromeImagePattern.hasMatch(normalizedUrl);

  static bool isImageAttachment(ForumPostAttachmentImage attachment) {
    if (attachment.attachimg.trim() == '1') return true;
    final extension = attachment.ext.trim().toLowerCase();
    if (_imageExtensions.contains(extension)) return true;
    final pathExtension = extensionFromPath(attachment.attachment);
    return pathExtension != null && _imageExtensions.contains(pathExtension);
  }

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

  static String? extensionFromPath(String path) {
    final cleanPath = path.split('?').first.split('#').first.trim();
    final dot = cleanPath.lastIndexOf('.');
    if (dot < 0 || dot == cleanPath.length - 1) return null;
    return cleanPath.substring(dot + 1).toLowerCase();
  }

  static bool isHttpImageUrl(String normalizedUrl) {
    final uri = Uri.tryParse(normalizedUrl);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

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
