import 'package:y300/features/thread/presentation/thread_post_text_slots.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
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

    final collector = ThreadPlainTextCollector();
    final pageSlots = _PageSlots.collect(source, collector);
    final postSlots = [
      for (final post in source.posts)
        ThreadPostTextSlots.collect(post, collector),
    ];
    final ratingSlots = <String, ThreadRatingDetailsTextSlots>{
      for (final entry in source.ratingsByPostId.entries)
        if (entry.value.status == ThreadPostRatingsLoadStatus.loaded &&
            entry.value.details != null)
          entry.key: ThreadRatingDetailsTextSlots.collect(
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
      parts.addAll(postRevisionParts(post));
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

  static Iterable<Object?> postRevisionParts(ThreadPost post) sync* {
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

final class _PageSlots {
  const _PageSlots({
    required this.subject,
    required this.forumName,
    required this.typeName,
    required this.sourceTagName,
  });

  factory _PageSlots.collect(
    ThreadDetailPageState source,
    ThreadPlainTextCollector collector,
  ) {
    return _PageSlots(
      subject: collector.add(source.subject),
      forumName: collector.addOptional(source.forumName),
      typeName: collector.addOptional(source.typeName),
      sourceTagName: collector.addOptional(source.sourceTagName),
    );
  }

  final ThreadTextSlot subject;
  final ThreadTextSlot? forumName;
  final ThreadTextSlot? typeName;
  final ThreadTextSlot? sourceTagName;
}
