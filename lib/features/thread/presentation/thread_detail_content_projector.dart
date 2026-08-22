import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';
import 'package:y300/features/thread/presentation/thread_content_projection_executor.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projection.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';

final class ThreadDetailContentProjector {
  const ThreadDetailContentProjector({
    required this.plainTextBatchConversionService,
    required this.htmlTextNodeConversionService,
    required this.diagnosticRecorder,
  });

  final PlainTextBatchConversionService plainTextBatchConversionService;
  final HtmlTextNodeConversionService htmlTextNodeConversionService;
  final TextConversionDiagnosticRecorder diagnosticRecorder;

  Future<ThreadDetailContentProjection> project(
    ThreadDetailPageState source, {
    required TextConverter converter,
  }) async {
    final revision = sourceRevisionFor(source);
    if (converter.mode == TextConversionMode.none) {
      return ThreadDetailContentProjection.raw(
        source,
        mode: converter.mode,
        converterId: converter.id,
        sourceRevision: revision,
      );
    }

    final collector = _ThreadPlainTextCollector();
    final pageSlots = _PageSlots.collect(source, collector);
    final postSlots = [
      for (final post in source.posts) _PostSlots.collect(post, collector),
    ];
    final ratingSlots = <String, _RatingDetailsSlots>{
      for (final entry in source.ratingsByPostId.entries)
        if (entry.value.status == ThreadPostRatingsLoadStatus.loaded &&
            entry.value.details != null)
          entry.key: _RatingDetailsSlots.collect(
            entry.value.details!,
            collector,
          ),
    };

    final batch =
        await ThreadContentProjectionExecutor(
          plainTextBatchConversionService: plainTextBatchConversionService,
          htmlTextNodeConversionService: htmlTextNodeConversionService,
          diagnosticRecorder: diagnosticRecorder,
        ).convert(
          plainSources: collector.sources,
          htmlFragments: [for (final post in source.posts) post.message],
          converter: converter,
          sourceRevision: revision,
        );
    if (!batch.succeeded ||
        batch.plainValues.length != collector.sources.length ||
        batch.htmlValues.length != source.posts.length) {
      return ThreadDetailContentProjection.raw(
        source,
        mode: converter.mode,
        converterId: converter.id,
        sourceRevision: revision,
      );
    }

    final displayPosts = <ThreadDetailPostProjection>[];
    for (var index = 0; index < source.posts.length; index += 1) {
      final sourcePost = source.posts[index];
      displayPosts.add(
        ThreadDetailPostProjection(
          sourcePost: sourcePost,
          displayPost: postSlots[index].build(
            sourcePost,
            values: batch.plainValues,
            displayHtml: batch.htmlValues[index].html,
          ),
        ),
      );
    }

    final displayRatings = <String, ThreadPostRatingsViewState>{
      ...source.ratingsByPostId,
    };
    for (final entry in ratingSlots.entries) {
      displayRatings[entry.key] = ThreadPostRatingsViewState.loaded(
        entry.value.build(
          source.ratingsByPostId[entry.key]!.details!,
          batch.plainValues,
        ),
      );
    }

    return ThreadDetailContentProjection(
      sourceState: source,
      displaySubject: pageSlots.subject.value(batch.plainValues),
      displayForumName: pageSlots.forumName?.value(batch.plainValues),
      displayTypeName: pageSlots.typeName?.value(batch.plainValues),
      displaySourceTagName: pageSlots.sourceTagName?.value(batch.plainValues),
      posts: displayPosts,
      displayRatingsByPostId: displayRatings,
      mode: converter.mode,
      converterId: converter.id,
      sourceRevision: revision,
      isConverted: true,
    );
  }

  static String sourceRevisionFor(ThreadDetailPageState source) {
    final parts = <Object?>[
      source.tid,
      source.fid,
      source.typeid,
      source.currentPage,
      source.capabilities?.paginationPrecision,
      source.readMetadata?.origin,
      source.readMetadata?.freshness,
      for (final entry
          in source.queryParameters.entries.toList()..sort(
            (left, right) => left.key.compareTo(right.key),
          )) ...[entry.key, entry.value],
      _textHash(source.subject),
      _textHash(source.forumName),
      _textHash(source.typeName),
      _textHash(source.sourceTagName),
    ];
    final capabilityEntries =
        source.capabilities?.values.values.entries.toList()
          ?..sort((left, right) => left.key.index.compareTo(right.key.index));
    for (final entry in capabilityEntries ?? const []) {
      parts
        ..add(entry.key)
        ..add(entry.value);
    }
    for (final post in source.posts) {
      parts.addAll(_postRevisionParts(post));
    }
    final ratingEntries = source.ratingsByPostId.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in ratingEntries) {
      final details = entry.value.status == ThreadPostRatingsLoadStatus.loaded
          ? entry.value.details
          : null;
      if (details == null) {
        continue;
      }
      parts
        ..add(entry.key)
        ..add(details.participantCount)
        ..add(_textHash(details.totalScoreText));
      for (final rating in details.ratings) {
        parts.addAll(_ratingRevisionParts(rating));
      }
    }
    return 'thread:${Object.hashAll(parts)}';
  }

  static Iterable<Object?> _postRevisionParts(ThreadPost post) sync* {
    yield post.pid;
    yield post.number;
    yield _textHash(post.author);
    yield post.authorId;
    yield _textHash(post.avatarUrl);
    yield _textHash(post.replyUrl);
    yield _textHash(post.editUrl);
    yield _textHash(post.rateUrl);
    yield _textHash(post.commentUrl);
    yield _textHash(post.message);
    yield _textHash(post.dateline);
    yield _textHash(post.rateSummary);
    for (final tag in post.tagLinks) {
      yield tag.tagId;
      yield _textHash(tag.label);
      yield _textHash(tag.url);
    }
    for (final attachment in post.attachmentImages) {
      yield attachment.aid;
      yield _textHash(attachment.filename);
      yield _textHash(attachment.url);
      yield _textHash(attachment.attachment);
      yield attachment.attachimg;
      yield attachment.ext;
    }
    final poll = post.poll;
    if (poll != null) {
      yield _textHash(poll.summary);
      yield _textHash(poll.deadlineText);
      yield _textHash(poll.statusText);
      yield _textHash(poll.actionUrl);
      yield _textHash(poll.formHash);
      for (final option in poll.options) {
        yield option.id;
        yield _textHash(option.label);
        yield option.voteCount;
        yield option.percent;
        yield option.colorHex;
      }
    }
    for (final comment in post.comments) {
      yield _textHash(comment.author);
      yield comment.authorId;
      yield _textHash(comment.authorUrl);
      yield _textHash(comment.avatarUrl);
      yield _textHash(comment.message);
      yield _textHash(comment.dateline);
    }
    final summary = post.ratingSummary;
    if (summary != null) {
      yield _textHash(summary.participantText);
      yield _textHash(summary.scoreText);
      for (final rating in summary.ratings) {
        yield* _ratingRevisionParts(rating);
      }
    }
  }

  static Iterable<Object?> _ratingRevisionParts(ThreadPostRating rating) sync* {
    yield _textHash(rating.userName);
    yield rating.userId;
    yield _textHash(rating.avatarUrl);
    yield _textHash(rating.score);
    yield _textHash(rating.reason);
    yield _textHash(rating.dateline);
  }

  static int _textHash(String? value) => Object.hashAll(<Object?>[value]);
}

final class _ThreadPlainTextCollector {
  final List<String> sources = <String>[];

  _TextSlot add(String value) {
    final slot = _TextSlot(sources.length);
    sources.add(value);
    return slot;
  }

  _TextSlot? addOptional(String? value) {
    return value == null ? null : add(value);
  }
}

final class _TextSlot {
  const _TextSlot(this.index);

  final int index;

  String value(List<String> values) => values[index];
}

final class _PageSlots {
  const _PageSlots({
    required this.subject,
    required this.forumName,
    required this.typeName,
    required this.sourceTagName,
  });

  factory _PageSlots.collect(
    ThreadDetailPageState source,
    _ThreadPlainTextCollector collector,
  ) {
    return _PageSlots(
      subject: collector.add(source.subject),
      forumName: collector.addOptional(source.forumName),
      typeName: collector.addOptional(source.typeName),
      sourceTagName: collector.addOptional(source.sourceTagName),
    );
  }

  final _TextSlot subject;
  final _TextSlot? forumName;
  final _TextSlot? typeName;
  final _TextSlot? sourceTagName;
}

final class _PostSlots {
  const _PostSlots({
    required this.dateline,
    required this.rateSummary,
    required this.tags,
    required this.attachments,
    required this.poll,
    required this.comments,
    required this.ratingSummary,
  });

  factory _PostSlots.collect(
    ThreadPost source,
    _ThreadPlainTextCollector collector,
  ) {
    return _PostSlots(
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

  final _TextSlot dateline;
  final _TextSlot? rateSummary;
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

  final _TextSlot label;

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

  final _TextSlot filename;

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
    _ThreadPlainTextCollector collector,
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

  final _TextSlot summary;
  final _TextSlot? deadlineText;
  final _TextSlot? statusText;
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
      actionUrl: source.actionUrl,
      formHash: source.formHash,
      statusText: statusText?.value(values),
    );
  }
}

final class _PollOptionSlots {
  const _PollOptionSlots({required this.label});

  final _TextSlot label;

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

  final _TextSlot message;
  final _TextSlot dateline;

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
    _ThreadPlainTextCollector collector,
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

  final _TextSlot participantText;
  final _TextSlot scoreText;
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
    _ThreadPlainTextCollector collector,
  ) {
    return _RatingSlots(
      score: collector.add(source.score),
      reason: collector.add(source.reason),
      dateline: collector.addOptional(source.dateline),
    );
  }

  final _TextSlot score;
  final _TextSlot reason;
  final _TextSlot? dateline;

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

final class _RatingDetailsSlots {
  const _RatingDetailsSlots({
    required this.totalScoreText,
    required this.ratings,
  });

  factory _RatingDetailsSlots.collect(
    ThreadPostRatingDetails source,
    _ThreadPlainTextCollector collector,
  ) {
    return _RatingDetailsSlots(
      totalScoreText: collector.add(source.totalScoreText),
      ratings: [
        for (final rating in source.ratings)
          _RatingSlots.collect(rating, collector),
      ],
    );
  }

  final _TextSlot totalScoreText;
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
