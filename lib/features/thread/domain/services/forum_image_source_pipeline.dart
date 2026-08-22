import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';

enum ForumImageSourceOrigin { dom, attachment }

enum ForumImageHostKind { yamiboAttachment, yamiboStatic, thirdParty, unknown }

class ForumImageSource {
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
}

class ForumImageSourceOptions {
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

abstract class ForumImageSourcePipeline {
  List<ForumImageSource> collectFromPost(
    ThreadPost post, {
    ForumImageSourceOptions options = const ForumImageSourceOptions(),
  });
}

class DefaultForumImageSourcePipeline implements ForumImageSourcePipeline {
  const DefaultForumImageSourcePipeline({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
    this.siteBaseUrl = AppConfig.siteBaseUrl,
  }) : _urlResolver = urlResolver;

  static final RegExp forumChromeImagePattern = RegExp(
    r'(smilies|static/image|emotion|avatar|uc_server/data/avatar)',
    caseSensitive: false,
  );

  final SiteUrlResolver _urlResolver;
  final String siteBaseUrl;

  @override
  List<ForumImageSource> collectFromPost(
    ThreadPost post, {
    ForumImageSourceOptions options = const ForumImageSourceOptions(),
  }) {
    final sources = <ForumImageSource>[];
    final seen = <String>{};

    for (final source in collectDomImageSources(
      post.message,
      urlResolver: _urlResolver,
      includeForumChrome: options.includeForumChrome,
      domAttributes: options.domAttributes,
      siteBaseUrl: siteBaseUrl,
    )) {
      if (seen.add(source.normalizedUrl)) {
        sources.add(source);
      }
    }

    if (!options.includeAttachments) {
      return sources;
    }

    for (final source in extractAttachmentSources(
      post,
      urlResolver: _urlResolver,
      siteBaseUrl: siteBaseUrl,
    )) {
      if (seen.add(source.normalizedUrl)) {
        sources.add(source);
      }
    }
    return sources;
  }

  static List<ForumImageSource> collectDomImageSources(
    String html, {
    required SiteUrlResolver urlResolver,
    bool includeForumChrome = false,
    List<String> domAttributes = ForumImageSourceOptions.defaultDomAttributes,
    String siteBaseUrl = AppConfig.siteBaseUrl,
  }) {
    final fragment = html_parser.parseFragment(html);
    final sources = <ForumImageSource>[];
    final seen = <String>{};
    var position = 0;
    for (final node in fragment.querySelectorAll('img')) {
      final rawUrl = firstDomImageSourceFromElement(
        node,
        domAttributes: domAttributes,
      );
      if (rawUrl == null || rawUrl.isEmpty) {
        continue;
      }
      final normalizedUrl = normalizeImageSource(
        rawUrl,
        urlResolver: urlResolver,
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
          position: position,
        ),
      );
      position += 1;
    }
    return sources;
  }

  static List<ForumImageSource> extractAttachmentSources(
    ThreadPost post, {
    required SiteUrlResolver urlResolver,
    String siteBaseUrl = AppConfig.siteBaseUrl,
  }) {
    final sources = <ForumImageSource>[];
    final seen = <String>{};
    var position = 0;
    for (final attachment in post.attachmentImages) {
      if (!isImageAttachment(attachment)) {
        continue;
      }
      final rawUrl = joinAttachmentUrl(attachment.url, attachment.attachment);
      final normalizedUrl = normalizeImageSource(
        rawUrl,
        urlResolver: urlResolver,
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
          position: position,
          aid: attachment.aid.trim().isEmpty ? null : attachment.aid.trim(),
        ),
      );
      position += 1;
    }
    return sources;
  }

  static String? normalizeImageSource(
    String rawUrl, {
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) {
    return urlResolver.resolve(rawUrl);
  }

  static String? firstDomImageSourceFromElement(
    html_dom.Element node, {
    List<String> domAttributes = ForumImageSourceOptions.defaultDomAttributes,
  }) {
    for (final attribute in domAttributes) {
      final value = node.attributes[attribute]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static bool isForumChromeImage(String normalizedUrl) {
    return forumChromeImagePattern.hasMatch(normalizedUrl);
  }

  static bool isImageAttachment(ForumPostAttachmentImage attachment) {
    if (attachment.attachimg.trim() == '1') {
      return true;
    }
    final ext = attachment.ext.trim().toLowerCase();
    if (ext.isNotEmpty && _imageExtensions.contains(ext)) {
      return true;
    }
    final pathExt = extensionFromPath(attachment.attachment);
    return pathExt != null && _imageExtensions.contains(pathExt);
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
    if (normalizedBase.isEmpty) {
      return normalizedAttachment;
    }
    if (normalizedBase.endsWith('/')) {
      return '$normalizedBase$normalizedAttachment';
    }
    return '$normalizedBase/$normalizedAttachment';
  }

  static String? extensionFromPath(String path) {
    final cleanPath = path.split('?').first.split('#').first.trim();
    final dot = cleanPath.lastIndexOf('.');
    if (dot < 0 || dot == cleanPath.length - 1) {
      return null;
    }
    return cleanPath.substring(dot + 1).toLowerCase();
  }

  static bool isHttpImageUrl(String normalizedUrl) {
    final uri = Uri.tryParse(normalizedUrl);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static ForumImageHostKind classifyHostKind(
    String normalizedUrl, {
    String siteBaseUrl = AppConfig.siteBaseUrl,
  }) {
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return ForumImageHostKind.unknown;
    }

    final siteHost = Uri.tryParse(siteBaseUrl)?.host.toLowerCase() ?? '';
    final normalizedHost = uri.host.toLowerCase();
    if (siteHost.isNotEmpty && normalizedHost == siteHost) {
      return uri.path.toLowerCase().startsWith('/data/attachment/')
          ? ForumImageHostKind.yamiboAttachment
          : ForumImageHostKind.yamiboStatic;
    }

    return normalizedHost.isEmpty
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

final forumImageSourcePipelineProvider = Provider<ForumImageSourcePipeline>((
  ref,
) {
  return const DefaultForumImageSourcePipeline();
});
