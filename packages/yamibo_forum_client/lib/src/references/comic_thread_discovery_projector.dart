import '../contracts/comic_contracts.dart';
import '../contracts/thread_detail_models.dart';
import 'forum_post_image_extractor.dart';

/// Projects a thread document into the source-neutral subset used by comic
/// discovery without exposing an API or HTML DTO to consumers.
final class ComicThreadDiscoveryProjector {
  /// Creates a [ComicThreadDiscoveryProjector].
  const ComicThreadDiscoveryProjector({
    this.imageSourcePipeline = const DefaultForumImageSourcePipeline(),
  });

  /// Image source pipeline.
  final ForumImageSourcePipeline imageSourcePipeline;

  /// Projects a validated thread document into comic discovery data.
  ComicThreadDiscoveryDocument project(ThreadDetailData detail) {
    final posts = detail.posts.toList(growable: false)
      ..sort((left, right) => left.number.compareTo(right.number));
    return ComicThreadDiscoveryDocument(
      tid: detail.tid.trim(),
      fid: detail.fid.trim(),
      typeId: detail.typeid.trim(),
      subject: detail.subject,
      posts: List<ComicThreadDiscoveryPost>.unmodifiable(
        posts.map(_projectPost),
      ),
    );
  }

  ComicThreadDiscoveryPost _projectPost(ThreadPost post) {
    final images = imageSourcePipeline.collectFromPost(post);
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
            attachmentId: source.attachmentId,
          ),
        ),
      ),
    );
  }
}
