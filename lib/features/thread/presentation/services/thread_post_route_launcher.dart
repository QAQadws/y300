import 'package:flutter/material.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:y300/features/thread/domain/services/thread_post_route_resolver.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';

enum _FailureChoice { retry, home }

Future<void> launchThreadPostRoute({
  required BuildContext context,
  required ThreadPostNavigationSession session,
  required ThreadPostRouteResolver resolver,
  required ThreadPostTarget target,
  required bool Function() isCurrent,
  String subject = '',
  Future<ApiResult<ThreadPostLocation>> Function()? resolve,
  Key failureDialogKey = const Key('thread-post-route-failure-dialog'),
}) {
  final ownerRoute = ModalRoute.of(context);
  return session.run(
    key: (target.tid, target.pid, target.landing),
    isCurrent: () => context.mounted && isCurrent(),
    action: (current) async {
      while (current() && (ownerRoute?.isCurrent ?? true)) {
        ApiResult<ThreadPostLocation> result;
        try {
          result = await (resolve?.call() ?? resolver.resolve(target));
        } catch (_) {
          result = const ApiFailure(
            ApiError(
              type: ApiErrorType.parse,
              message: 'thread_post_target_unconfirmed',
            ),
          );
        }
        if (!context.mounted ||
            !current() ||
            !(ownerRoute?.isCurrent ?? true)) {
          return;
        }
        if (result case ApiSuccess(:final data)) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ThreadDetailPage(
                tid: data.tid,
                targetPid: data.pid,
                landing: target.landing,
                initialPage: data.page,
                subject: subject,
              ),
            ),
          );
          return;
        }
        final l10n = AppLocalizations.of(context);
        final error = result.errorOrNull!;
        final choice = await showDialog<_FailureChoice>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            key: failureDialogKey,
            title: Text(l10n.threadPostLocationFailedTitle),
            content: Text(threadPostLocationFailureText(l10n, error)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.commonCancel),
              ),
              if (RegExp(r'^[1-9]\d*$').hasMatch(target.tid))
                TextButton(
                  key: const Key('thread-post-route-open-home'),
                  onPressed: () =>
                      Navigator.pop(dialogContext, _FailureChoice.home),
                  child: Text(l10n.threadPostOpenHome),
                ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _FailureChoice.retry),
                child: Text(l10n.commonRetry),
              ),
            ],
          ),
        );
        if (!context.mounted ||
            !current() ||
            !(ownerRoute?.isCurrent ?? true)) {
          return;
        }
        if (choice == _FailureChoice.retry) continue;
        if (choice == _FailureChoice.home) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ThreadDetailPage(tid: target.tid, subject: subject),
            ),
          );
        }
        return;
      }
    },
  );
}

String threadPostLocationFailureText(AppLocalizations l10n, ApiError error) {
  if (error.type == ApiErrorType.unauthorized) return l10n.threadLoginRequired;
  if (error.statusCode == 403 ||
      error.code == 'thread_post_location_permission_denied') {
    return l10n.threadPermissionDenied;
  }
  if (error.type == ApiErrorType.network ||
      error.type == ApiErrorType.timeout ||
      error.type == ApiErrorType.server) {
    return l10n.threadPostLocationNetworkFailed;
  }
  return l10n.threadPostTargetUnconfirmed;
}
