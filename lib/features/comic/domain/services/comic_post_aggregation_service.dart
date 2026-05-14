import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_attachment_image_extractor.dart';

final comicPostAggregationServiceProvider = Provider<ComicPostAggregationService>((ref) {
  return const ComicPostAggregationService();
});

/// 漫画候选聚合策略：
/// 1. 始终纳入首楼。
/// 2. 若二楼同为楼主且二楼“以图片为主”，则将二楼并入解析与判定输入。
class ComicPostAggregationService {
  const ComicPostAggregationService({
    ForumAttachmentImageExtractor attachmentImageExtractor = const ForumAttachmentImageExtractor(),
  }) : _attachmentImageExtractor = attachmentImageExtractor;

  final ForumAttachmentImageExtractor _attachmentImageExtractor;

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

    final ThreadPost? mergedSecond = shouldMergeSecond ? second : null;
    final detectionMessage = mergedSecond != null
        ? '${first.message}\n${mergedSecond.message}'
        : first.message;

    final parseMessage = detectionMessage;
    final attachmentImageUrls = _mergeAttachmentImages(
      mergedSecond == null ? <ThreadPost>[first] : <ThreadPost>[first, mergedSecond],
    );

    return ComicPostAggregationResult(
      detectionMessage: detectionMessage,
      parseMessage: parseMessage,
      attachmentImageUrls: attachmentImageUrls,
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

  /// “多数图片”工程化定义：
  /// - 图片至少 2 张；
  /// - 图片标签数量 >= 链接标签数量。
  bool _isImageDominant(ThreadPost post) {
    final message = post.message;
    final imageCount = RegExp(r'<img\b', caseSensitive: false).allMatches(message).length;
    final anchorCount = RegExp(r'<a\b', caseSensitive: false).allMatches(message).length;
    final attachmentImageCount = _attachmentImageExtractor.extractImageUrls(post).length;
    final totalImageCount = imageCount + attachmentImageCount;
    return totalImageCount >= 2 && totalImageCount >= anchorCount;
  }

  List<String> _mergeAttachmentImages(List<ThreadPost> posts) {
    final urls = <String>[];
    final seen = <String>{};
    for (final post in posts) {
      for (final imageUrl in _attachmentImageExtractor.extractImageUrls(post)) {
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
