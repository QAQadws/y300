import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../client/forum_client_config.dart';
import '../contracts/thread_detail_models.dart';
import '../url/forum_uri_resolver.dart';

enum ForumImageSourceOrigin { dom, attachment }

final class ForumImageSource {
  const ForumImageSource({
    required this.normalizedUrl,
    required this.origin,
    this.attachmentId,
  });

  final String normalizedUrl;
  final ForumImageSourceOrigin origin;
  final String? attachmentId;
}

/// Extracts the stable image projection shared by comic adapters.
///
/// DOM images retain document order. Structured attachments are appended and
/// duplicate normalized URLs are removed without exposing the source DTO.
final class ForumImageSourcePipeline {
  ForumImageSourcePipeline(ForumClientConfig config)
    : _resolver = ForumUriResolver(siteOrigin: config.siteOrigin);

  final ForumUriResolver _resolver;

  List<ForumImageSource> collectFromPost(ThreadPost post) {
    final result = <ForumImageSource>[];
    final seen = <String>{};
    final fragment = html_parser.parseFragment(post.message);
    for (final image in fragment.querySelectorAll('img')) {
      final raw = _firstSource(image);
      if (raw == null) continue;
      final normalized = _normalize(raw);
      if (normalized == null ||
          _isForumChrome(normalized) ||
          !seen.add(normalized)) {
        continue;
      }
      result.add(
        ForumImageSource(
          normalizedUrl: normalized,
          origin: ForumImageSourceOrigin.dom,
        ),
      );
    }

    for (final attachment in post.attachmentImages) {
      if (!_isImageAttachment(attachment)) continue;
      final normalized = _normalize(
        _joinAttachmentUrl(attachment.url, attachment.attachment),
      );
      if (normalized == null || !seen.add(normalized)) continue;
      final aid = attachment.aid.trim();
      result.add(
        ForumImageSource(
          normalizedUrl: normalized,
          origin: ForumImageSourceOrigin.attachment,
          attachmentId: aid.isEmpty ? null : aid,
        ),
      );
    }
    return List<ForumImageSource>.unmodifiable(result);
  }

  String? _firstSource(html_dom.Element image) {
    for (final attribute in _domAttributes) {
      final value = image.attributes[attribute]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _normalize(String raw) {
    try {
      final uri = _resolver.resolve(raw);
      if (uri.scheme != 'http' && uri.scheme != 'https') return null;
      return uri.toString();
    } on FormatException {
      return null;
    }
  }

  bool _isForumChrome(String url) => _forumChromeImagePattern.hasMatch(url);

  bool _isImageAttachment(ForumPostAttachmentImage attachment) {
    if (attachment.attachimg.trim() == '1') return true;
    final extension = attachment.ext.trim().toLowerCase();
    if (_imageExtensions.contains(extension)) return true;
    final path = attachment.attachment.split('?').first.split('#').first;
    final dot = path.lastIndexOf('.');
    return dot >= 0 &&
        dot < path.length - 1 &&
        _imageExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  String _joinAttachmentUrl(String base, String attachment) {
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

  static const _domAttributes = <String>[
    'src',
    'data-src',
    'data-original',
    'file',
  ];
  static final _forumChromeImagePattern = RegExp(
    r'(smilies|static/image|emotion|avatar|uc_server/data/avatar)',
    caseSensitive: false,
  );
  static const _imageExtensions = <String>{'jpg', 'jpeg', 'png', 'gif', 'webp'};
}
