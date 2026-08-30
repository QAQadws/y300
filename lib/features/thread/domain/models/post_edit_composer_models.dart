import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

enum PostEditWebReturnVerificationState {
  idle,
  verifying,
  unchanged,
  changedClean,
  conflict,
  unconfirmed,
}

final class PostEditConflictState {
  const PostEditConflictState({
    required this.localSubject,
    required this.localMessage,
    required this.localUseSignature,
    required this.localImageAttachments,
    required this.localAttachmentSession,
    required this.latestSnapshot,
  });

  final String localSubject;
  final String localMessage;
  final bool localUseSignature;
  final List<ComposerImageAttachment> localImageAttachments;
  final PostEditAttachmentSession localAttachmentSession;
  final ThreadPostEditPreparation latestSnapshot;
}

enum PostEditSubmitState {
  idle,
  submitting,
  verifying,
  partialSuccess,
  unconfirmed,
}

enum PostEditRouteOutcome {
  dismissed,
  saved,
  partialSuccess,
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
