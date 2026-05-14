import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_attachment_image_extractor.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

/// Collects all image URLs exposed by a Discuz post.
///
/// Message HTML and attachment metadata are two different transport formats
/// for the same comic page images, so callers should depend on this collector
/// instead of re-implementing merge and de-duplication rules.
class ForumPostImageSourceCollector {
  const ForumPostImageSourceCollector({
    ForumPostDomExtractor domExtractor = const ForumPostDomExtractor(),
    ForumAttachmentImageExtractor attachmentImageExtractor = const ForumAttachmentImageExtractor(),
  })  : _domExtractor = domExtractor,
        _attachmentImageExtractor = attachmentImageExtractor;

  final ForumPostDomExtractor _domExtractor;
  final ForumAttachmentImageExtractor _attachmentImageExtractor;

  List<String> collect(ThreadPost post) {
    return merge(
      domImageUrls: _domExtractor.extractImageSources(post.message),
      attachmentImageUrls: _attachmentImageExtractor.extractImageUrls(post),
    );
  }

  List<String> merge({
    required List<String> domImageUrls,
    required List<String> attachmentImageUrls,
  }) {
    final urls = <String>[];
    final seen = <String>{};
    for (final imageUrl in <String>[...domImageUrls, ...attachmentImageUrls]) {
      if (imageUrl.trim().isNotEmpty && seen.add(imageUrl)) {
        urls.add(imageUrl);
      }
    }
    return urls;
  }
}
