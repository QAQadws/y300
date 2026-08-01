import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

final comicPostAggregationServiceProvider =
    Provider<ComicPostAggregationService>((ref) {
      return ComicPostAggregationService(
        imageSourcePipeline: ref.watch(forumImageSourcePipelineProvider),
      );
    });

/// Comic candidate aggregation rules:
/// 1. Always include floor 1.
/// 2. Merge floor 2 only when it is from the OP and remains image-dominant.
class ComicPostAggregationService {
  const ComicPostAggregationService({
    ForumImageSourcePipeline imageSourcePipeline =
        const DefaultForumImageSourcePipeline(),
  }) : _imageSourcePipeline = imageSourcePipeline;

  final ForumImageSourcePipeline _imageSourcePipeline;

  ComicPostAggregationResult build(List<ThreadPost> posts) {
    final first = _firstFloor(posts);
    if (first == null) {
      return const ComicPostAggregationResult(
        detectionMessage: '',
        parseMessage: '',
        attachmentImageUrls: <String>[],
      );
    }

    final second = _secondFloor(posts);
    final shouldMergeSecond =
        second != null &&
        second.authorId == first.authorId &&
        _isImageDominant(second);

    final mergedSecond = shouldMergeSecond ? second : null;
    final detectionMessage = mergedSecond != null
        ? '${first.message}\n${mergedSecond.message}'
        : first.message;

    return ComicPostAggregationResult(
      detectionMessage: detectionMessage,
      parseMessage: detectionMessage,
      attachmentImageUrls: _mergeAttachmentImages(
        mergedSecond == null
            ? <ThreadPost>[first]
            : <ThreadPost>[first, mergedSecond],
      ),
      usedSecondFloor: shouldMergeSecond,
      secondFloorPid: mergedSecond?.pid,
    );
  }

  ThreadPost? _firstFloor(List<ThreadPost> posts) {
    for (final post in posts) {
      if (post.isFirst || post.number == 1) {
        return post;
      }
    }
    return null;
  }

  ThreadPost? _secondFloor(List<ThreadPost> posts) {
    for (final post in posts) {
      if (post.number == 2) {
        return post;
      }
    }
    return null;
  }

  bool _isImageDominant(ThreadPost post) {
    final imageCount = _imageSourcePipeline.collectFromPost(post).length;
    final anchorCount = RegExp(
      r'<a\b',
      caseSensitive: false,
    ).allMatches(post.message).length;
    return imageCount >= 2 && imageCount >= anchorCount;
  }

  List<String> _mergeAttachmentImages(List<ThreadPost> posts) {
    final urls = <String>[];
    final seen = <String>{};
    for (final post in posts) {
      final sources = _imageSourcePipeline.collectFromPost(post);
      for (final imageUrl
          in sources
              .where(
                (source) => source.origin == ForumImageSourceOrigin.attachment,
              )
              .map((source) => source.normalizedUrl)) {
        if (seen.add(imageUrl)) {
          urls.add(imageUrl);
        }
      }
    }
    return urls;
  }
}

class ComicPostAggregationResult {
  const ComicPostAggregationResult({
    required this.detectionMessage,
    required this.parseMessage,
    required this.attachmentImageUrls,
    this.usedSecondFloor = false,
    this.secondFloorPid,
  });

  final String detectionMessage;
  final String parseMessage;
  final List<String> attachmentImageUrls;
  final bool usedSecondFloor;
  final String? secondFloorPid;
}
