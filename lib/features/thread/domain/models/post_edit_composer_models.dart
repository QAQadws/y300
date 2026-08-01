import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

enum PostEditWebReturnVerificationState {
  idle,
  verifying,
  unchanged,
  changedClean,
  conflict,
  unconfirmed,
}

final class PostEditDraftConflict {
  const PostEditDraftConflict({
    required this.localDraft,
    required this.latestSnapshot,
  });

  final ComposerDraftSnapshot localDraft;
  final PostEditFormSnapshot latestSnapshot;
}

enum PostEditRouteOutcome {
  dismissed,
  webViewReturned,
  serverChanged,
  unconfirmed,
}

final class PostEditRouteResult {
  const PostEditRouteResult({
    required this.target,
    required this.outcome,
    this.serverMutationPossible = false,
  });

  final PostEditTarget target;
  final PostEditRouteOutcome outcome;
  final bool serverMutationPossible;
}
