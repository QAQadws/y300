import 'package:y300/features/comic/domain/models/comic_thread_discovery_models.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

/// Projects a full thread result into the stable subset needed by comic
/// discovery. Source-specific thread fields stop at this data boundary.
final class ComicThreadDiscoveryDocumentMapper {
  const ComicThreadDiscoveryDocumentMapper({
    ForumImageSourcePipeline imageSourcePipeline =
        const DefaultForumImageSourcePipeline(),
  }) : _imageSourcePipeline = imageSourcePipeline;

  final ForumImageSourcePipeline _imageSourcePipeline;

  ComicThreadDiscoveryDocument map(ThreadDetailData detail) {
    final orderedPosts = detail.posts.toList(growable: false)
      ..sort((left, right) => left.number.compareTo(right.number));
    return ComicThreadDiscoveryDocument(
      tid: detail.tid.trim(),
      fid: detail.fid.trim(),
      typeId: detail.typeid.trim(),
      subject: detail.subject,
      posts: List<ComicThreadDiscoveryPost>.unmodifiable(
        orderedPosts.map(_mapPost),
      ),
    );
  }

  ComicThreadDiscoveryPost _mapPost(ThreadPost post) {
    final images = _imageSourcePipeline.collectFromPost(post);
    return ComicThreadDiscoveryPost(
      pid: post.pid.trim(),
      authorId: post.authorId.trim(),
      floorNumber: post.number,
      isFirst: post.isFirst,
      messageHtml: post.message,
      imageReferences: List<ComicThreadDiscoveryImageReference>.unmodifiable(
        images.map(
          (source) => ComicThreadDiscoveryImageReference(
            url: source.normalizedUrl,
            origin: switch (source.origin) {
              ForumImageSourceOrigin.dom => ComicEpisodeImageOrigin.dom,
              ForumImageSourceOrigin.attachment =>
                ComicEpisodeImageOrigin.attachment,
            },
            attachmentId: source.aid,
          ),
        ),
      ),
    );
  }
}
