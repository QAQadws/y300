import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/data/providers/thread_interaction_providers.dart';
import 'package:y300/features/thread/presentation/thread_post_interaction_models.dart';

final threadPostRatingServiceProvider = Provider<ThreadPostRatingService>(
  (ref) => ThreadPostRatingService(
    ref.watch(threadPostRatingPreparationProvider),
    ref.watch(threadPostRatingCommandProvider),
  ),
);

class ThreadPostRatingService {
  const ThreadPostRatingService(this._preparation, this._command);
  final ThreadPostRatingPreparationRepository _preparation;
  final ThreadPostRatingCommand _command;

  Future<DataReadResult<ThreadPostRateForm, ThreadPostRatingCapabilities>>
  load({required String tid, required ThreadPost post, Uri? referer}) async {
    if (post.pid.trim().isEmpty || post.rateUrl?.trim().isNotEmpty != true) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'thread_post_rating_entry_missing',
        diagnosticMessage: 'thread_post_rating_entry_missing',
      );
    }
    final result = await _preparation.load(
      ThreadPostRatingPreparationRequest(
        tid: tid,
        pid: post.pid,
        referer: referer,
      ),
    );
    if (result
        case DataReadFailure<
              ThreadPostRatingPreparation,
              ThreadPostRatingCapabilities
            >()) {
      return result.failureOrNull!.retype();
    }
    final success =
        result
            as DataReadSuccess<
              ThreadPostRatingPreparation,
              ThreadPostRatingCapabilities
            >;
    if (success.data.dimensions.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'thread_post_rating_dimensions_missing',
        diagnosticMessage: 'thread_post_rating_dimensions_missing',
      );
    }
    return DataReadSuccess(
      data: ThreadPostRateForm(
        preparation: success.data,
        dimension: success.data.dimensions.first,
      ),
      capabilities: success.capabilities,
      metadata: success.metadata,
    );
  }

  Future<DataCommandResult<ThreadPostRatingReceipt>> submit(
    ThreadPostRateDraft draft,
  ) => _command.execute(draft.toSubmission());
}
