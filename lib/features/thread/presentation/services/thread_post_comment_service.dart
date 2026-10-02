import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/data/providers/thread_interaction_providers.dart';
import 'package:y300/features/thread/presentation/thread_post_interaction_models.dart';

final threadPostCommentServiceProvider = Provider(
  (ref) => ThreadPostCommentService(
    ref.watch(threadPostCommentPreparationProvider),
    ref.watch(threadPostCommentCommandProvider),
  ),
);

class ThreadPostCommentService {
  const ThreadPostCommentService(this._preparation, this._command);
  final ThreadPostCommentPreparationRepository _preparation;
  final ThreadPostCommentCommand _command;
  Future<DataReadResult<ThreadPostCommentForm, ThreadPostCommentCapabilities>>
  load({
    required String tid,
    required int page,
    required ThreadPost post,
    Uri? referer,
  }) async {
    final pid = post.pid.trim();
    if (pid.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'thread_post_comment_pid_missing',
        diagnosticMessage: 'thread_post_comment_pid_missing',
      );
    }
    final commentUrl = post.commentUrl?.trim();
    if (commentUrl == null || commentUrl.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'thread_post_comment_entry_missing',
        diagnosticMessage: 'thread_post_comment_entry_missing',
      );
    }
    final result = await _preparation.load(
      ThreadPostCommentPreparationRequest(
        tid: tid,
        pid: pid,
        page: page <= 0 ? 1 : page,
        referer: referer,
      ),
    );
    return switch (result) {
      DataReadFailure<
        ThreadPostCommentPreparation,
        ThreadPostCommentCapabilities
      >() =>
        result.failureOrNull!.retype(),
      DataReadSuccess<
        ThreadPostCommentPreparation,
        ThreadPostCommentCapabilities
      >(
        :final data,
        :final capabilities,
        :final metadata,
      ) =>
        DataReadSuccess(
          data: ThreadPostCommentForm(preparation: data),
          capabilities: capabilities,
          metadata: metadata,
        ),
    };
  }

  Future<DataCommandResult<ThreadPostCommentReceipt>> submit(
    ThreadPostCommentDraft draft,
  ) => _command.execute(draft.toSubmission());
}
