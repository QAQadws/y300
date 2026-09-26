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
    required this.onLogin,
    required this.onLogout,
    required this.onOpenProfile,
    this.isAccountActionPending = false,
  });

  final VoidCallback onLogin;
  final VoidCallback onLogout;
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
    final busy = verifying || loggingOut || isAccountActionPending;
    final action = signedIn
        ? IconButton(
            key: const Key('more-logout-entry'),
            onPressed: busy ? null : onLogout,
            tooltip: l10n.moreLogout,
            icon: loggingOut
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout, size: 20),
          )
        : TextButton.icon(
            key: const Key('more-login-entry'),
            onPressed: busy ? null : onLogin,
            icon: const Icon(Icons.login, size: 20),
            label: Text(l10n.moreLogin),
          );
    final openProfile = owner != null && !busy ? onOpenProfile : null;
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          label: l10n.moreAccountAvatar(name),
          image: true,
          child: InkWell(
            key: const Key('more-account-avatar'),
            customBorder: const CircleBorder(),
            onTap: openProfile,
            child: ForumCachedAvatar(
              key: ValueKey(
                'more-account-avatar-${owner?.uid}-${owner?.revision}',
              ),
              imageUrl: avatarUrl,
              ownerId: owner?.uid ?? '',
              ownerType: ImageCacheOwnerType.profile,
              size: 56,
              imageReferer: ref.watch(forumImageRefererProvider),
              fallbackPolicy: ForumAvatarFallbackPolicy.localDefaultAvatar,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: openProfile == null
                    ? null
                    : l10n.moreAccountOpenProfile(name),
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              if (owner != null) ...[
                if (groupName != null) ...[
                  const SizedBox(height: 4),
                  Semantics(
                    label: l10n.moreAccountGroup(groupName),
                    excludeSemantics: true,
                    child: Container(
                      key: const Key('more-account-group'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        groupName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  l10n.moreAccountCredits(
                    credits?.toString() ?? l10n.moreAccountUnavailable,
                  ),
                  key: const Key('more-account-credits'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else if (!verifying && !loggingOut)
                Text(
                  l10n.moreLoginSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Card(
      key: const Key('more-account-header'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(14) > 18;
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      identity,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 12),
                    action,
                  ],
                );
              },
            ),
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
