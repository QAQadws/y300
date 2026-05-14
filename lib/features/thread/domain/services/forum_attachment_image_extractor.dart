import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

/// Extracts image URLs from Discuz mobile-api attachment metadata.
///
/// Some older comic posts keep the real pages only in `postlist.attachments`.
/// Keeping this separate from DOM parsing makes the source of each image clear
/// and lets all comic parsing paths share the same attachment URL rules.
class ForumAttachmentImageExtractor {
  const ForumAttachmentImageExtractor({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  static const Set<String> _imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
  };

  final SiteUrlResolver _urlResolver;

  List<String> extractImageUrls(ThreadPost post) {
    final urls = <String>[];
    final seen = <String>{};
    for (final attachment in post.attachmentImages) {
      if (!_isImageAttachment(attachment)) {
        continue;
      }
      final raw = _joinUrl(attachment.url, attachment.attachment);
      final normalized = _urlResolver.resolve(raw);
      if (normalized != null && normalized.isNotEmpty && seen.add(normalized)) {
        urls.add(normalized);
      }
    }
    return urls;
  }

  bool _isImageAttachment(ForumPostAttachmentImage attachment) {
    if (attachment.attachimg.trim() == '1') {
      return true;
    }
    final ext = attachment.ext.trim().toLowerCase();
    if (ext.isNotEmpty && _imageExtensions.contains(ext)) {
      return true;
    }
    final pathExt = _extensionFromPath(attachment.attachment);
    return pathExt != null && _imageExtensions.contains(pathExt);
  }

  String _joinUrl(String base, String attachment) {
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

  String? _extensionFromPath(String path) {
    final cleanPath = path.split('?').first.split('#').first.trim();
    final dot = cleanPath.lastIndexOf('.');
    if (dot < 0 || dot == cleanPath.length - 1) {
      return null;
    }
    return cleanPath.substring(dot + 1).toLowerCase();
  }
}
