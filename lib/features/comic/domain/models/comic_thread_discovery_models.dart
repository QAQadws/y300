import 'package:y300/features/comic/domain/models/comic_episode_image_catalog.dart';

final class ComicThreadDiscoveryRequest {
  const ComicThreadDiscoveryRequest({required this.sourceTid});

  final String sourceTid;
}

final class ComicThreadDiscoveryImageReference {
  const ComicThreadDiscoveryImageReference({
    required this.url,
    required this.origin,
    this.attachmentId,
  });

  final String url;
  final ComicEpisodeImageOrigin origin;
  final String? attachmentId;
}

final class ComicThreadDiscoveryPost {
  const ComicThreadDiscoveryPost({
    required this.pid,
    required this.authorId,
    required this.floorNumber,
    required this.isFirst,
    required this.messageHtml,
    required this.imageReferences,
  });

  final String pid;
  final String authorId;
  final int floorNumber;
  final bool isFirst;
  final String messageHtml;
  final List<ComicThreadDiscoveryImageReference> imageReferences;
}

final class ComicThreadDiscoveryDocument {
  const ComicThreadDiscoveryDocument({
    required this.tid,
    required this.fid,
    required this.typeId,
    required this.subject,
    required this.posts,
  });

  final String tid;
  final String fid;
  final String typeId;
  final String subject;
  final List<ComicThreadDiscoveryPost> posts;
}
