import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_surface.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

class FriendLoginPrompt extends StatelessWidget {
  const FriendLoginPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = Theme.of(context).y300NativeContent;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 40, color: palette.muted),
            const SizedBox(height: 12),
            Text(
              l10n.profileFriendsLoginRequired,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.supportingText),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('my-friends-login'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              ),
              child: Text(l10n.authLoginTitle),
            ),
          ],
        ),
      ),
    );
  }
}

class FriendReadFailure extends StatelessWidget {
  const FriendReadFailure({
    super.key,
    required this.failure,
    required this.onRetry,
  });

  final DataReadFailure<ForumFriendFeedPage, ForumFriendFeedReadCapabilities>?
  failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (failure?.kind == DataReadFailureKind.unauthorized) {
      return const FriendLoginPrompt();
    }
    final l10n = AppLocalizations.of(context);
    final palette = Theme.of(context).y300NativeContent;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 34, color: palette.muted),
          const SizedBox(height: 12),
          Text(
            failure == null
                ? l10n.profileFriendsLoadFailed
                : LocalizedErrorSummary.resolve(l10n, failure),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.supportingText),
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('my-friends-retry'),
            onPressed: onRetry,
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}

class FriendEmptyState extends StatelessWidget {
  const FriendEmptyState({super.key, required this.scope});

  final ForumFriendFeedScope scope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = Theme.of(context).y300NativeContent;
    final text = switch (scope) {
      ForumFriendFeedScope.friends => l10n.profileFriendsEmpty,
      ForumFriendFeedScope.online => l10n.profileFriendsOnlineEmpty,
      ForumFriendFeedScope.visitors => l10n.profileFriendsVisitorsEmpty,
      ForumFriendFeedScope.footprints => l10n.profileFriendsFootprintsEmpty,
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 40, color: palette.muted),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.supportingText),
          ),
        ],
      ),
    );
  }
}

/// Stays above the scrollable list while a sent removal awaits verification.
class FriendRemovalVerification extends StatelessWidget {
  const FriendRemovalVerification({
    super.key,
    required this.isBusy,
    required this.onVerify,
  });

  final bool isBusy;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: BlogSurface(
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.profileFriendRemovalUnknown,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.y300NativeContent.supportingText,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('my-friends-removal-verify'),
                  onPressed: isBusy ? null : onVerify,
                  child: Text(l10n.profileFriendRemovalVerify),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
