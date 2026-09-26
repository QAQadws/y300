import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/profile/presentation/current_account_summary_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

/// Account presentation stays independent of the menu's navigation flows.
class MoreAccountHeader extends ConsumerWidget {
  const MoreAccountHeader({
    super.key,
    required this.onOpenProfile,
    this.isAccountActionPending = false,
  });

  final VoidCallback? onOpenProfile;
  final bool isAccountActionPending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionControllerProvider);
    final session = auth.asData?.value;
    final owner = ref.watch(verifiedProfileOwnerProvider);
    final summary = ref.watch(currentAccountSummaryControllerProvider);
    final current = owner != null && summary.owner == owner;
    final data = current ? summary.data : null;
    final capabilities = current ? summary.capabilities : null;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final signedIn = session?.isLoggedIn == true;
    final loggingOut = session?.isLoggingOut == true;
    final verifying =
        auth.isLoading || (signedIn && owner == null && !loggingOut);
    final displayName =
        capabilities?.supports(CurrentUserProfileCapability.userName) == true
        ? data?.identity.displayName
        : null;
    final name = owner == null
        ? verifying || loggingOut
              ? l10n.moreAccountChecking
              : l10n.moreAccountSignedOut
        : _nonEmpty(displayName) ??
              _nonEmpty(session?.username) ??
              l10n.moreAccountSignedIn;
    final avatarUrl =
        capabilities?.supports(CurrentUserProfileCapability.avatarReference) ==
            true
        ? data?.avatarUrl
        : null;
    final groupName =
        capabilities?.supports(CurrentUserProfileCapability.groupName) == true
        ? _nonEmpty(data?.groupName)
        : null;
    final credits =
        capabilities?.supports(CurrentUserProfileCapability.creditTotal) == true
        ? data?.creditTotal
        : null;
    final threads =
        capabilities?.supports(CurrentUserProfileCapability.threadCount) == true
        ? data?.threadCount
        : null;
    final replies =
        capabilities?.supports(CurrentUserProfileCapability.replyCount) == true
        ? data?.replyCount
        : null;
    final busy = verifying || loggingOut || isAccountActionPending;
    final openProfile = owner != null && !busy ? onOpenProfile : null;
    final avatar = Semantics(
      label: l10n.moreAccountAvatar(name),
      image: true,
      child: InkWell(
        key: const Key('more-account-avatar'),
        customBorder: const CircleBorder(),
        onTap: openProfile,
        child: ForumCachedAvatar(
          key: ValueKey('more-account-avatar-${owner?.uid}-${owner?.revision}'),
          imageUrl: avatarUrl,
          ownerId: owner?.uid ?? '',
          ownerType: ImageCacheOwnerType.profile,
          size: owner != null ? 72 : 56,
          imageReferer: ref.watch(forumImageRefererProvider),
          fallbackPolicy: ForumAvatarFallbackPolicy.localDefaultAvatar,
        ),
      ),
    );
    final identityChildren = <Widget>[
      Semantics(
        label: openProfile == null ? null : l10n.moreAccountOpenProfile(name),
        child: InkWell(
          key: const Key('more-account-name'),
          onTap: openProfile,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: owner != null ? 20 : null,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      if (owner != null && groupName != null)
        Semantics(
          label: l10n.moreAccountGroup(groupName),
          excludeSemantics: true,
          child: Container(
            key: const Key('more-account-group'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              groupName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        )
      else if (owner == null && !verifying && !loggingOut)
        Text(
          l10n.moreLoginSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
    ];
    final identity = owner != null
        ? Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: identityChildren,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: identityChildren,
          );

    return Card(
      key: const Key('more-account-header'),
      margin: const EdgeInsets.only(top: 12),
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: owner != null
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.center,
              children: [
                avatar,
                if (owner != null) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _AccountStatistic(
                              key: const Key('more-account-threads'),
                              label: l10n.moreAccountThreads,
                              value: threads,
                            ),
                          ),
                          const VerticalDivider(
                            width: 16,
                            indent: 8,
                            endIndent: 8,
                          ),
                          Expanded(
                            child: _AccountStatistic(
                              key: const Key('more-account-replies'),
                              label: l10n.moreAccountReplies,
                              value: replies,
                            ),
                          ),
                          const VerticalDivider(
                            width: 16,
                            indent: 8,
                            endIndent: 8,
                          ),
                          Expanded(
                            child: _AccountStatistic(
                              key: const Key('more-account-credits'),
                              label: l10n.moreAccountCreditLabel,
                              value: credits,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 12),
                  Expanded(child: identity),
                ],
              ],
            ),
            if (owner != null) ...[const SizedBox(height: 8), identity],
            if (verifying || (current && summary.isLoading)) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                key: Key('more-account-loading'),
                minHeight: 2,
              ),
            ],
            if (current && summary.failure != null)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    l10n.moreAccountLoadFailed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    key: const Key('more-account-retry'),
                    onPressed: summary.isLoading
                        ? null
                        : () => ref
                              .read(
                                currentAccountSummaryControllerProvider
                                    .notifier,
                              )
                              .refresh(),
                    child: Text(l10n.commonRetry),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _AccountStatistic extends StatelessWidget {
  const _AccountStatistic({super.key, required this.label, this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = value?.toString() ?? l10n.moreAccountUnavailable;
    return Semantics(
      label: l10n.moreAccountStatistic(label, text),
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
