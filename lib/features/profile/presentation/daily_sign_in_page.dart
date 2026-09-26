import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/domain/daily_sign_in_attempt_ledger.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Standalone presentation of the shared sign-in panel.
class DailySignInPage extends StatelessWidget {
  const DailySignInPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).dailySignInTitle)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: const <Widget>[DailySignInPanel()],
    ),
  );
}

/// Source-neutral sign-in state and actions for a verified owner only.
class DailySignInPanel extends ConsumerStatefulWidget {
  const DailySignInPanel({super.key, this.showCard = true});

  final bool showCard;

  @override
  ConsumerState<DailySignInPanel> createState() => _DailySignInPanelState();
}

class _DailySignInPanelState extends ConsumerState<DailySignInPanel> {
  late final ProviderSubscription<VerifiedProfileOwner?> _ownerSubscription;
  int _ownerLoadRevision = 0;

  @override
  void initState() {
    super.initState();
    _ownerSubscription = ref.listenManual(verifiedProfileOwnerProvider, (
      _,
      owner,
    ) {
      final revision = ++_ownerLoadRevision;
      if (owner == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            revision != _ownerLoadRevision ||
            ref.read(verifiedProfileOwnerProvider) != owner) {
          return;
        }
        // Page entry and session changes share any status read already started
        // by startup automation.
        unawaited(ref.read(dailySignInControllerProvider.notifier).refresh());
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _ownerSubscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(verifiedProfileOwnerProvider);
    final state = ref.watch(dailySignInControllerProvider);
    final l10n = AppLocalizations.of(context);
    final current = state.owner == owner
        ? state
        : DailySignInViewState(owner: owner);
    final snapshot = owner == null ? null : current.snapshot;
    final failure = current.readFailure;
    final commandMessage = _commandMessage(l10n, current);
    final canAct = owner != null && !current.isLoading && !current.isSubmitting;
    final canSign =
        canAct &&
        !current.storageUnavailable &&
        snapshot?.status == ForumDailySignInStatus.unsigned &&
        failure == null;
    final offerWebFallback =
        failure?.kind == DataReadFailureKind.parse ||
        failure?.kind == DataReadFailureKind.unsupported;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dailySignInTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (owner == null)
          Text(l10n.dailySignInLoginRequired)
        else if (current.isLoading ||
            (snapshot == null && failure == null)) ...[
          const LinearProgressIndicator(key: Key('daily-sign-in-progress')),
          const SizedBox(height: 8),
          Text(l10n.dailySignInChecking),
        ] else if (snapshot != null)
          Text(
            snapshot.status == ForumDailySignInStatus.signed
                ? l10n.dailySignInSigned
                : l10n.dailySignInUnsigned,
            key: const Key('daily-sign-in-status'),
          )
        else
          Text(
            failure?.kind == DataReadFailureKind.unauthorized
                ? l10n.dailySignInLoginRequired
                : failure?.kind == DataReadFailureKind.unsupported
                ? l10n.dailySignInPluginUnavailable
                : l10n.dailySignInFailed,
            key: const Key('daily-sign-in-read-error'),
          ),
        if (current.isSubmitting) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(key: Key('daily-sign-in-submitting')),
          const SizedBox(height: 8),
          Text(l10n.dailySignInSubmitting),
        ],
        if (commandMessage != null) ...[
          const SizedBox(height: 8),
          Text(commandMessage, key: const Key('daily-sign-in-command-message')),
        ],
        if (owner != null) ...[
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            key: const Key('daily-auto-sign-in-toggle'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.dailyAutoSignInToggle),
            subtitle: Text(
              current.isSavingAutoPreference
                  ? l10n.dailyAutoSignInSaving
                  : l10n.dailyAutoSignInDescription,
            ),
            value: current.autoEnabled ?? false,
            onChanged:
                current.autoEnabled != null &&
                    !current.isSavingAutoPreference &&
                    !current.settingsUnavailable
                ? (enabled) => unawaited(
                    ref
                        .read(dailySignInControllerProvider.notifier)
                        .setAutomaticEnabled(enabled),
                  )
                : null,
          ),
          if (current.storageUnavailable)
            Text(
              l10n.dailyAutoSignInStorageUnavailable,
              key: const Key('daily-sign-in-storage-error'),
            )
          else if (snapshot?.status == ForumDailySignInStatus.unsigned &&
              current.automaticPolicy ==
                  DailySignInAutomaticPolicy.pausedPreviousDay)
            Text(
              l10n.dailyAutoSignInPausedPreviousDay,
              key: const Key('daily-auto-sign-in-paused'),
            )
          else if (snapshot?.status == ForumDailySignInStatus.unsigned &&
              current.automaticPolicy ==
                  DailySignInAutomaticPolicy.blockedToday &&
              current.commandResult == null)
            Text(
              current.checkpointState == DailySignInAttemptState.pending ||
                      current.checkpointState == DailySignInAttemptState.unknown
                  ? l10n.dailyAutoSignInPendingToday
                  : l10n.dailyAutoSignInBlockedToday,
              key: const Key('daily-auto-sign-in-blocked'),
            ),
        ],
        if (snapshot?.statistics case final statistics?
            when statistics.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l10n.dailySignInStatistics,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          for (final statistic in statistics)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(statistic.label)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(statistic.value, textAlign: TextAlign.end),
                  ),
                ],
              ),
            ),
        ],
        if (owner != null) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canSign)
                FilledButton(
                  key: const Key('daily-sign-in-submit'),
                  onPressed: () {
                    if (current.needsExplicitRetry) {
                      unawaited(_confirmRetry(context, ref, owner));
                    } else {
                      unawaited(
                        ref
                            .read(dailySignInControllerProvider.notifier)
                            .submit(),
                      );
                    }
                  },
                  child: Text(
                    current.needsExplicitRetry
                        ? l10n.dailySignInRetryUnknown
                        : l10n.dailySignInSignNow,
                  ),
                ),
              OutlinedButton(
                key: const Key('daily-sign-in-refresh'),
                onPressed: canAct
                    ? () => unawaited(
                        ref
                            .read(dailySignInControllerProvider.notifier)
                            .refresh(),
                      )
                    : null,
                child: Text(
                  current.commandResult
                          is DataCommandOutcomeUnknown<ForumDailySignInReceipt>
                      ? l10n.dailySignInVerify
                      : l10n.dailySignInRefresh,
                ),
              ),
              if (offerWebFallback)
                TextButton(
                  key: const Key('daily-sign-in-web-fallback'),
                  onPressed: () => _openForumPage(context, ref),
                  child: Text(l10n.dailySignInOpenForum),
                ),
            ],
          ),
        ],
      ],
    );
    return widget.showCard
        ? Card(
            key: const Key('daily-sign-in-panel'),
            child: Padding(padding: const EdgeInsets.all(16), child: content),
          )
        : KeyedSubtree(key: const Key('daily-sign-in-panel'), child: content);
  }
}

String? _commandMessage(AppLocalizations l10n, DailySignInViewState state) {
  final result = state.commandResult;
  if (result is DataCommandApplied<ForumDailySignInReceipt>) {
    return l10n.dailySignInApplied;
  }
  if (result is DataCommandOutcomeUnknown<ForumDailySignInReceipt>) {
    return state.attemptForumDay == state.snapshot?.forumDay &&
            state.snapshot?.status == ForumDailySignInStatus.signed
        ? l10n.dailySignInUnknownButSigned
        : l10n.dailySignInOutcomeUnknown;
  }
  if (result is DataCommandRejected<ForumDailySignInReceipt>) {
    if (result.failure.kind == DataCommandFailureKind.permissionDenied) {
      return l10n.dailySignInPermissionDenied;
    }
    if (result.failure.code == 'daily_sign_in_time_window_closed') {
      return l10n.dailySignInTimeWindowClosed;
    }
    return l10n.dailySignInRejected;
  }
  if (result is DataCommandNotSent<ForumDailySignInReceipt>) {
    return result.failure.code == 'daily_sign_in_forum_day_changed'
        ? l10n.dailySignInDayChanged
        : l10n.dailySignInNotSent;
  }
  if (result is DataCommandUnsupported<ForumDailySignInReceipt>) {
    return l10n.dailySignInPluginUnavailable;
  }
  return null;
}

Future<void> _confirmRetry(
  BuildContext context,
  WidgetRef ref,
  VerifiedProfileOwner owner,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.dailySignInRetryTitle),
      content: Text(l10n.dailySignInRetryBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('daily-sign-in-confirm-retry'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.dailySignInRetryUnknown),
        ),
      ],
    ),
  );
  if (confirmed == true &&
      context.mounted &&
      ref.read(verifiedProfileOwnerProvider) == owner) {
    await ref
        .read(dailySignInControllerProvider.notifier)
        .submit(explicitlyRetryUnknown: true);
  }
}

void _openForumPage(BuildContext context, WidgetRef ref) {
  final uri = Uri.parse(AppConfig.siteBaseUrl).replace(
    path: '/plugin.php',
    queryParameters: const <String, String>{'id': 'zqlj_sign', 'mobile': '2'},
  );
  Navigator.of(context).push(
    ref.read(forumWebViewRouteFactoryProvider)(
      ForumWebViewLaunchConfig(initialUri: uri, popOnRootBack: true),
    ),
  );
}
