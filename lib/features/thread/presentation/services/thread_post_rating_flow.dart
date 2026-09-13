import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';
import 'package:y300/features/thread/presentation/thread_post_interaction_models.dart';
import 'package:y300/features/thread/presentation/thread_post_rate_form_projection.dart';
import 'package:y300/features/thread/presentation/thread_text_resolver.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

/// Reuses the same form, display projection, sheet and feedback at every entry.
/// The caller owns successful-write invalidation and its screen's refresh.
Future<DataCommandResult<ThreadPostRatingReceipt>?> showThreadPostRatingFlow({
  required BuildContext context,
  required WidgetRef ref,
  required Future<
    DataReadResult<ThreadPostRateForm, ThreadPostRatingCapabilities>
  >
  Function()
  load,
  required Future<DataCommandResult<ThreadPostRatingReceipt>> Function(
    ThreadPostRateDraft,
  )
  submit,
  required bool Function() isCurrent,
}) async {
  final formResult = await load();
  if (!context.mounted || !isCurrent()) return null;
  if (formResult
      case DataReadFailure<ThreadPostRateForm, ThreadPostRatingCapabilities>(
        :final kind,
      )) {
    showTransientSnackBar(
      context,
      ThreadTextResolver.actionFailure(
        AppLocalizations.of(context),
        ThreadActionFailure(
          code: kind == DataReadFailureKind.unauthorized
              ? ThreadUiErrorCode.loginRequired
              : ThreadUiErrorCode.rateFailed,
          action: ThreadActionKind.rate,
        ),
      ),
    );
    return null;
  }
  final mode = ref.read(appServerContentConversionModeProvider);
  final projection =
      await ThreadPostRateFormProjector(
        plainTextBatchConversionService: ref.read(
          plainTextBatchConversionServiceProvider,
        ),
      ).project(
        formResult.dataOrNull!,
        converter: ref.read(textConverterProvider(mode)),
      );
  if (!context.mounted || !isCurrent()) return null;
  final draft = await showModalBottomSheet<ThreadPostRateDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ThreadPostRateSheet(projection: projection),
  );
  if (!context.mounted || !isCurrent() || draft == null) return null;
  final result = await submit(draft);
  if (!context.mounted || !isCurrent()) return result;
  final code = switch (result) {
    DataCommandApplied<ThreadPostRatingReceipt>() =>
      ThreadActionNoticeCode.success,
    DataCommandOutcomeUnknown<ThreadPostRatingReceipt>() =>
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
        action: ThreadActionKind.rate,
        commandFailure: result.failureOrNull,
      ),
    ),
  );
  return result;
}
