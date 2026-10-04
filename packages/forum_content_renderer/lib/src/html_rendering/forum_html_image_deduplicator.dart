import 'package:html/dom.dart' as html_dom;
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Removes duplicated Discuz attachment images from an HTML fragment.
///
/// `ThreadPost.message` can contain the same attachment once from the body and
/// once from Discuz's attachment gallery. The HTML pipeline normalizes obvious
/// attachment image URLs here while leaving repeated stickers/chrome images
/// untouched.
class ForumHtmlImageDeduplicator {
  const ForumHtmlImageDeduplicator({
    required String? Function(String) resolveUrl,
  }) : _resolveUrl = resolveUrl;

  final String? Function(String) _resolveUrl;

  int deduplicateAttachmentImagesInFragment(
    html_dom.DocumentFragment fragment,
  ) {
    final seen = <String>{};
    var removedCount = 0;

    for (final image in fragment.querySelectorAll('img')) {
      final key = _attachmentImageKey(image);
      if (key == null) {
        continue;
      }
      if (seen.add(key)) {
        continue;
      }
      image.remove();
      removedCount++;
    }
    return removedCount;
  }

  String? _attachmentImageKey(html_dom.Element image) {
    final rawUrl =
        DefaultForumImageSourcePipeline.firstDomImageSourceFromElement(
          image,
          domAttributes: const <String>[
            'zoomfile',
            'file',
            'data-original',
            'data-src',
            'src',
          ],
        );
    if (rawUrl == null || rawUrl.isEmpty) {
      return null;
    }
    final normalized = DefaultForumImageSourcePipeline.normalizeImageSource(
      rawUrl,
      urlResolver: _resolveUrl,
    );
    if (normalized == null ||
        !DefaultForumImageSourcePipeline.isHttpImageUrl(normalized) ||
        DefaultForumImageSourcePipeline.isForumChromeImage(normalized) ||
        !_looksLikeForumAttachmentImage(image, normalized)) {
      return null;
    }
    return Uri.tryParse(normalized)?.removeFragment().toString() ?? normalized;
  }

  bool _looksLikeForumAttachmentImage(
    html_dom.Element image,
    String normalizedUrl,
  ) {
    if ((image.attributes['aid'] ?? '').trim().isNotEmpty) {
      return true;
    }
    if (image.id.trim().startsWith('aimg_')) {
      return true;
    }
    if ((image.attributes['zoomfile'] ?? '').trim().isNotEmpty ||
        (image.attributes['file'] ?? '').trim().isNotEmpty) {
      return true;
    }
    final uri = Uri.tryParse(normalizedUrl);
    return uri?.path.toLowerCase().startsWith('/data/attachment/') ?? false;
  }
}
