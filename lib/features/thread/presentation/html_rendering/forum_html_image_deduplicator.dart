import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

/// Removes duplicated Discuz attachment images from an HTML fragment.
///
/// `ThreadPost.message` can contain the same attachment once from the body and
/// once from Discuz's attachment gallery. The legacy renderer dedupes through
/// its render plan; HTML-first renders the fragment directly, so we normalize
/// obvious attachment image URLs here while leaving repeated stickers/chrome
/// images untouched.
class ForumHtmlImageDeduplicator {
  const ForumHtmlImageDeduplicator({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  String deduplicateAttachmentImages(String html) {
    if (!html.contains('<img')) {
      return html;
    }

    final fragment = html_parser.parseFragment(html);
    final removedCount = deduplicateAttachmentImagesInFragment(fragment);
    if (removedCount == 0) {
      return html;
    }
    return fragment.nodes.map(_serializeNode).join();
  }

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
      urlResolver: _urlResolver,
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

  String _serializeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      return node.outerHtml;
    }
    if (node is html_dom.Text) {
      return const HtmlEscape().convert(node.data);
    }
    return node.text ?? '';
  }
}
