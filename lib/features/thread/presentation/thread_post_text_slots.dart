import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';

final class ThreadPlainTextCollector {
  final List<String> sources = <String>[];

  ThreadTextSlot add(String value) {
    final slot = ThreadTextSlot(sources.length);
    sources.add(value);
    return slot;
  }

  ThreadTextSlot? addOptional(String? value) {
    return value == null ? null : add(value);
  }
}

final class ThreadTextSlot {
  const ThreadTextSlot(this.index);

  final int index;

  String value(List<String> values) => values[index];
}

final class _ThreadPostTextSlots {
  const _ThreadPostTextSlots({
    required this.dateline,
    required this.rateSummary,
    required this.tags,
    required this.attachments,
    required this.poll,
    required this.comments,
    required this.ratingSummary,
  });

  factory _ThreadPostTextSlots.collect(
    ThreadPost source,
    ThreadPlainTextCollector collector,
  ) {
    return _ThreadPostTextSlots(
      dateline: collector.add(source.dateline),
      rateSummary: collector.addOptional(source.rateSummary),
      tags: [
        for (final tag in source.tagLinks)
          _TagSlots(label: collector.add(tag.label)),
      ],
      attachments: [
        for (final attachment in source.attachmentImages)
          _AttachmentSlots(filename: collector.add(attachment.filename)),
      ],
      poll: source.poll == null
          ? null
          : _PollSlots.collect(source.poll!, collector),
      comments: [
        for (final comment in source.comments)
          _CommentSlots(
            message: collector.add(comment.message),
            dateline: collector.add(comment.dateline),
          ),
      ],
      ratingSummary: source.ratingSummary == null
          ? null
          : _RatingSummarySlots.collect(source.ratingSummary!, collector),
    );
  }

  final ThreadTextSlot dateline;
  final ThreadTextSlot? rateSummary;
  final List<_TagSlots> tags;
  final List<_AttachmentSlots> attachments;
  final _PollSlots? poll;
  final List<_CommentSlots> comments;
  final _RatingSummarySlots? ratingSummary;

  ThreadPost build(
    ThreadPost source, {
    required List<String> values,
    required String displayHtml,
  }) {
    return ThreadPost(
      pid: source.pid,
      author: source.author,
      authorId: source.authorId,
      message: displayHtml,
      number: source.number,
      isFirst: source.isFirst,
      dateline: dateline.value(values),
      avatarUrl: source.avatarUrl,
      replyUrl: source.replyUrl,
      editUrl: source.editUrl,
      rateUrl: source.rateUrl,
      commentUrl: source.commentUrl,
      rateSummary: rateSummary?.value(values),
      ratingSummary: ratingSummary?.build(source.ratingSummary!, values),
      poll: poll?.build(source.poll!, values),
      tagLinks: [
        for (var index = 0; index < source.tagLinks.length; index += 1)
          tags[index].build(source.tagLinks[index], values),
      ],
      comments: [
        for (var index = 0; index < source.comments.length; index += 1)
          comments[index].build(source.comments[index], values),
      ],
      attachmentImages: [
        for (var index = 0; index < source.attachmentImages.length; index += 1)
          attachments[index].build(source.attachmentImages[index], values),
      ],
    );
  }
}

final class _TagSlots {
  const _TagSlots({required this.label});

  final ThreadTextSlot label;

  ThreadPostTagLink build(ThreadPostTagLink source, List<String> values) {
    return ThreadPostTagLink(
      label: label.value(values),
      url: source.url,
      tagId: source.tagId,
    );
  }
}

final class _AttachmentSlots {
  const _AttachmentSlots({required this.filename});

  final ThreadTextSlot filename;

  ForumPostAttachmentImage build(
    ForumPostAttachmentImage source,
    List<String> values,
  ) {
    return ForumPostAttachmentImage(
      aid: source.aid,
      url: source.url,
      attachment: source.attachment,
      filename: filename.value(values),
      attachimg: source.attachimg,
      ext: source.ext,
    );
  }
}

final class _PollSlots {
  const _PollSlots({
    required this.summary,
    required this.deadlineText,
    required this.statusText,
    required this.options,
  });

  factory _PollSlots.collect(
    ThreadPoll source,
    ThreadPlainTextCollector collector,
  ) {
    return _PollSlots(
      summary: collector.add(source.summary),
      deadlineText: collector.addOptional(source.deadlineText),
      statusText: collector.addOptional(source.statusText),
      options: [
        for (final option in source.options)
          _PollOptionSlots(label: collector.add(option.label)),
      ],
    );
  }

  final ThreadTextSlot summary;
  final ThreadTextSlot? deadlineText;
  final ThreadTextSlot? statusText;
  final List<_PollOptionSlots> options;

  ThreadPoll build(ThreadPoll source, List<String> values) {
    return ThreadPoll(
      isMultipleChoice: source.isMultipleChoice,
      summary: summary.value(values),
      options: [
        for (var index = 0; index < source.options.length; index += 1)
          options[index].build(source.options[index], values),
      ],
      canVote: source.canVote,
      maxChoices: source.maxChoices,
      deadlineText: deadlineText?.value(values),
      statusText: statusText?.value(values),
    );
  }
}

final class _PollOptionSlots {
  const _PollOptionSlots({required this.label});

  final ThreadTextSlot label;

  ThreadPollOption build(ThreadPollOption source, List<String> values) {
    return ThreadPollOption(
      id: source.id,
      label: label.value(values),
      voteCount: source.voteCount,
      percent: source.percent,
      colorHex: source.colorHex,
    );
  }
}

final class _CommentSlots {
  const _CommentSlots({required this.message, required this.dateline});

  final ThreadTextSlot message;
  final ThreadTextSlot dateline;

  ThreadPostCommentEntry build(
    ThreadPostCommentEntry source,
    List<String> values,
  ) {
    return ThreadPostCommentEntry(
      author: source.author,
      message: message.value(values),
      dateline: dateline.value(values),
      authorId: source.authorId,
      authorUrl: source.authorUrl,
      avatarUrl: source.avatarUrl,
    );
  }
}

final class _RatingSummarySlots {
  const _RatingSummarySlots({
    required this.participantText,
    required this.scoreText,
    required this.ratings,
  });

  factory _RatingSummarySlots.collect(
    ThreadPostRatingSummary source,
    ThreadPlainTextCollector collector,
  ) {
    return _RatingSummarySlots(
      participantText: collector.add(source.participantText),
      scoreText: collector.add(source.scoreText),
      ratings: [
        for (final rating in source.ratings)
          _RatingSlots.collect(rating, collector),
      ],
    );
  }

  final ThreadTextSlot participantText;
  final ThreadTextSlot scoreText;
  final List<_RatingSlots> ratings;

  ThreadPostRatingSummary build(
    ThreadPostRatingSummary source,
    List<String> values,
  ) {
    return ThreadPostRatingSummary(
      participantText: participantText.value(values),
      scoreText: scoreText.value(values),
      ratings: [
        for (var index = 0; index < source.ratings.length; index += 1)
          ratings[index].build(source.ratings[index], values),
      ],
      viewAllUrl: source.viewAllUrl,
    );
  }
}

final class _RatingSlots {
  const _RatingSlots({
    required this.score,
    required this.reason,
    required this.dateline,
  });

  factory _RatingSlots.collect(
    ThreadPostRating source,
    ThreadPlainTextCollector collector,
  ) {
    return _RatingSlots(
      score: collector.add(source.score),
      reason: collector.add(source.reason),
      dateline: collector.addOptional(source.dateline),
    );
  }

  final ThreadTextSlot score;
  final ThreadTextSlot reason;
  final ThreadTextSlot? dateline;

  ThreadPostRating build(ThreadPostRating source, List<String> values) {
    return ThreadPostRating(
      userName: source.userName,
      score: score.value(values),
      reason: reason.value(values),
      userId: source.userId,
      avatarUrl: source.avatarUrl,
      dateline: dateline?.value(values),
    );
  }
}

final class _ThreadRatingDetailsTextSlots {
  const _ThreadRatingDetailsTextSlots({
    required this.totalScoreText,
    required this.ratings,
  });

  factory _ThreadRatingDetailsTextSlots.collect(
    ThreadPostRatingDetails source,
    ThreadPlainTextCollector collector,
  ) {
    return _ThreadRatingDetailsTextSlots(
      totalScoreText: collector.add(source.totalScoreText),
      ratings: [
        for (final rating in source.ratings)
          _RatingSlots.collect(rating, collector),
      ],
    );
  }

  final ThreadTextSlot totalScoreText;
  final List<_RatingSlots> ratings;

  ThreadPostRatingDetails build(
    ThreadPostRatingDetails source,
    List<String> values,
  ) {
    return ThreadPostRatingDetails(
      participantCount: source.participantCount,
      totalScoreText: totalScoreText.value(values),
      ratings: [
        for (var index = 0; index < source.ratings.length; index += 1)
          ratings[index].build(source.ratings[index], values),
      ],
    );
  }
}

final class ThreadPostTextSlots {
  ThreadPostTextSlots.collect(
    ThreadPost source,
    ThreadPlainTextCollector collector,
  ) : _slots = _ThreadPostTextSlots.collect(source, collector);
  final _ThreadPostTextSlots _slots;
  ThreadTextSlot get dateline => _slots.dateline;
  ThreadPost build(
    ThreadPost source, {
    required List<String> values,
    required String displayHtml,
  }) => _slots.build(source, values: values, displayHtml: displayHtml);
}

final class ThreadRatingDetailsTextSlots {
  ThreadRatingDetailsTextSlots.collect(
    ThreadPostRatingDetails source,
    ThreadPlainTextCollector collector,
  ) : _slots = _ThreadRatingDetailsTextSlots.collect(source, collector);
  final _ThreadRatingDetailsTextSlots _slots;
  ThreadPostRatingDetails build(
    ThreadPostRatingDetails source,
    List<String> values,
  ) => _slots.build(source, values);
}
