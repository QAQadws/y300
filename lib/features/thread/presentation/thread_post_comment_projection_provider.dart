import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';

final class ThreadPostCommentProjection {
  const ThreadPostCommentProjection({
    required this.sourceLists,
    required this.displayLists,
  });

  final Map<String, List<ThreadPostCommentEntry>> sourceLists;
  final Map<String, List<ThreadPostCommentEntry>> displayLists;

  bool matches(Map<String, ThreadPostCommentsViewState> current) {
    if (sourceLists.length != current.length) return false;
    for (final entry in current.entries) {
      if (!identical(sourceLists[entry.key], entry.value.comments)) {
        return false;
      }
    }
    return true;
  }
}

/// Projects only transient continuation comments, leaving long post bodies
/// outside the conversion batch when a new comment page arrives.
final threadPostCommentProjectionProvider = FutureProvider.autoDispose
    .family<ThreadPostCommentProjection, ThreadDetailArgs>((ref, args) async {
      final states = ref.watch(
        threadDetailControllerProvider(
          args,
        ).select((value) => value.value?.commentsByPostId ?? const {}),
      );
      final mode = ref.watch(appServerContentConversionModeProvider);
      final converter = ref.watch(textConverterProvider(mode));
      final sourceLists = {
        for (final entry in states.entries) entry.key: entry.value.comments,
      };
      if (mode == TextConversionMode.none || states.isEmpty) {
        return ThreadPostCommentProjection(
          sourceLists: sourceLists,
          displayLists: sourceLists,
        );
      }
      final comments = <(String, ThreadPostCommentEntry)>[
        for (final entry in states.entries)
          for (final comment in entry.value.comments) (entry.key, comment),
      ];
      if (comments.isEmpty) {
        return ThreadPostCommentProjection(
          sourceLists: sourceLists,
          displayLists: sourceLists,
        );
      }
      try {
        final values = await ref
            .read(plainTextBatchConversionServiceProvider)
            .convertAll(
              sources: [
                for (final (_, comment) in comments) ...[
                  comment.author,
                  comment.dateline,
                  comment.message,
                ],
              ],
              converter: converter,
            );
        if (values.length != comments.length * 3) throw const FormatException();
        final result = <String, List<ThreadPostCommentEntry>>{};
        for (var index = 0; index < comments.length; index++) {
          final (pid, source) = comments[index];
          result
              .putIfAbsent(pid, () => [])
              .add(
                ThreadPostCommentEntry(
                  author: values[index * 3],
                  dateline: values[index * 3 + 1],
                  message: values[index * 3 + 2],
                  authorId: source.authorId,
                  authorUrl: source.authorUrl,
                  avatarUrl: source.avatarUrl,
                  commentId: source.commentId,
                ),
              );
        }
        return ThreadPostCommentProjection(
          sourceLists: sourceLists,
          displayLists: result,
        );
      } catch (_) {
        return ThreadPostCommentProjection(
          sourceLists: sourceLists,
          displayLists: sourceLists,
        );
      }
    });
