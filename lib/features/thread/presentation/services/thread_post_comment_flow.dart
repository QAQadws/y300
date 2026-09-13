import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';
import 'package:y300/features/thread/presentation/thread_post_interaction_models.dart';
import 'package:y300/features/thread/presentation/thread_text_resolver.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

/// Reuses the same form, display projection, sheet and feedback at every entry.
/// The caller owns successful-write invalidation and its screen's refresh.
Future<DataCommandResult<ThreadPostCommentReceipt>?> showThreadPostCommentFlow({
  required BuildContext context,
  required WidgetRef ref,
  required Future<
    DataReadResult<ThreadPostCommentForm, ThreadPostCommentCapabilities>
  >
  Function()
  load,
  required Future<DataCommandResult<ThreadPostCommentReceipt>> Function(
    ThreadPostCommentDraft,
  )
  submit,
  required bool Function() isCurrent,
}) async {
  final formResult = await load();
  if (!context.mounted || !isCurrent()) return null;
  if (formResult case DataReadFailure<
    ThreadPostCommentForm,
    ThreadPostCommentCapabilities
  >(
    :final kind,
  )) {
    showTransientSnackBar(
      context,
      ThreadTextResolver.actionFailure(
        AppLocalizations.of(context),
        ThreadActionFailure(
          code: kind == DataReadFailureKind.unauthorized
              ? ThreadUiErrorCode.loginRequired
              : ThreadUiErrorCode.commentFailed,
          action: ThreadActionKind.comment,
        ),
      ),
    );
    return null;
  }
  final draft = await showModalBottomSheet<ThreadPostCommentDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ThreadPostCommentSheet(form: formResult.dataOrNull!),
  );
  if (!context.mounted || !isCurrent() || draft == null) return null;
  final result = await submit(draft);
  if (!context.mounted || !isCurrent()) return result;
  final code = switch (result) {
    DataCommandApplied<ThreadPostCommentReceipt>() =>
      ThreadActionNoticeCode.success,
    DataCommandOutcomeUnknown<ThreadPostCommentReceipt>() =>
      ThreadActionNoticeCode.unknown,
    _ => switch (result.failureOrNull?.kind) {
      DataCommandFailureKind.unauthenticated =>
        ThreadActionNoticeCode.loginRequired,
      DataCommandFailureKind.permissionDenied =>
        ThreadActionNoticeCode.permissionDenied,
      DataCommandFailureKind.unsupported => ThreadActionNoticeCode.unsupported,
      _ => ThreadActionNoticeCode.failure,
    },
  };
  showTransientSnackBar(
    context,
    ThreadTextResolver.actionNotice(
      AppLocalizations.of(context),
      ThreadActionNotice(
        code: code,
        action: ThreadActionKind.comment,
        commandFailure: result.failureOrNull,
      ),
    ),
  );
  return result;
}
