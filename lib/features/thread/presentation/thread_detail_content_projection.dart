import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';

final class ThreadDetailContentProjection {
  ThreadDetailContentProjection({
    required this.sourceState,
    required this.displaySubject,
    required this.displayForumName,
    required this.displayTypeName,
    required this.displaySourceTagName,
    required List<ThreadDetailPostProjection> posts,
    required Map<String, ThreadPostRatingsViewState> displayRatingsByPostId,
    required this.mode,
    required this.converterId,
    required this.sourceRevision,
    required this.isConverted,
  }) : posts = List<ThreadDetailPostProjection>.unmodifiable(posts),
       displayRatingsByPostId =
           Map<String, ThreadPostRatingsViewState>.unmodifiable(
             displayRatingsByPostId,
           );

  factory ThreadDetailContentProjection.raw(
    ThreadDetailPageState source, {
    required TextConversionMode mode,
    required String converterId,
    required String sourceRevision,
  }) {
    return ThreadDetailContentProjection(
      sourceState: source,
      displaySubject: source.subject,
      displayForumName: source.forumName,
      displayTypeName: source.typeName,
      displaySourceTagName: source.sourceTagName,
      posts: [
        for (final post in source.posts)
          ThreadDetailPostProjection(sourcePost: post, displayPost: post),
      ],
      displayRatingsByPostId: source.ratingsByPostId,
      mode: mode,
      converterId: converterId,
      sourceRevision: sourceRevision,
      isConverted: false,
    );
  }

  final ThreadDetailPageState sourceState;
  final String displaySubject;
  final String? displayForumName;
  final String? displayTypeName;
  final String? displaySourceTagName;
  final List<ThreadDetailPostProjection> posts;
  final Map<String, ThreadPostRatingsViewState> displayRatingsByPostId;
  final TextConversionMode mode;
  final String converterId;
  final String sourceRevision;
  final bool isConverted;

  String get displayIdentity =>
      '${mode.name}:$converterId:$sourceRevision:${isConverted ? 1 : 0}';

  List<ThreadPost> get displayPosts =>
      List<ThreadPost>.unmodifiable(posts.map((item) => item.displayPost));

  ThreadDetailPostProjection? findByPid(String pid) {
    final normalized = pid.trim();
    for (final post in posts) {
      if (post.sourcePost.pid.trim() == normalized) {
        return post;
      }
    }
    return null;
  }

  /// Reuses converted display fields while rebasing transient controller
  /// states that are intentionally excluded from [sourceRevision].
  ThreadDetailContentProjection rebaseTransientState(
    ThreadDetailPageState source,
  ) {
    final ratings = <String, ThreadPostRatingsViewState>{};
    for (final entry in source.ratingsByPostId.entries) {
      ratings[entry.key] =
          entry.value.status == ThreadPostRatingsLoadStatus.loaded
          ? displayRatingsByPostId[entry.key] ?? entry.value
          : entry.value;
    }
    final rebasedPosts = <ThreadDetailPostProjection>[];
    for (var index = 0; index < posts.length; index += 1) {
      final projected = posts[index];
      final current =
          index < source.posts.length &&
              source.posts[index].pid == projected.sourcePost.pid
          ? source.posts[index]
          : projected.sourcePost;
      rebasedPosts.add(
        ThreadDetailPostProjection(
          sourcePost: current,
          displayPost: projected.displayPost,
        ),
      );
    }
    return ThreadDetailContentProjection(
      sourceState: source,
      displaySubject: displaySubject,
      displayForumName: displayForumName,
      displayTypeName: displayTypeName,
      displaySourceTagName: displaySourceTagName,
      posts: rebasedPosts,
      displayRatingsByPostId: ratings,
      mode: mode,
      converterId: converterId,
      sourceRevision: sourceRevision,
      isConverted: isConverted,
    );
  }
}

final class ThreadDetailPostProjection {
  const ThreadDetailPostProjection({
    required this.sourcePost,
    required this.displayPost,
  });

  final ThreadPost sourcePost;
  final ThreadPost displayPost;

  ThreadPollOption? sourcePollOption(String optionId) {
    final poll = sourcePost.poll;
    if (poll == null) {
      return null;
    }
    for (final option in poll.options) {
      if (option.id == optionId) {
        return option;
      }
    }
    return null;
  }

  ThreadPostCommentEntry? sourceCommentFor(
    ThreadPostCommentEntry displayComment,
  ) {
    final index = displayPost.comments.indexOf(displayComment);
    if (index < 0 || index >= sourcePost.comments.length) {
      return null;
    }
    return sourcePost.comments[index];
  }
}
