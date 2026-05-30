import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

/// Collects all image URLs exposed by a Discuz post.
///
/// Message HTML and attachment metadata are two different transport formats
/// for the same comic page images, so callers should depend on this collector
/// instead of re-implementing merge and de-duplication rules.
class ForumPostImageSourceCollector {
  const ForumPostImageSourceCollector({
    ForumImageSourcePipeline imageSourcePipeline =
        const DefaultForumImageSourcePipeline(),
  }) : _imageSourcePipeline = imageSourcePipeline;

  final ForumImageSourcePipeline _imageSourcePipeline;

  List<String> collect(ThreadPost post) {
    return _imageSourcePipeline
        .collectFromPost(post)
        .map((source) => source.normalizedUrl)
        .toList(growable: false);
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
