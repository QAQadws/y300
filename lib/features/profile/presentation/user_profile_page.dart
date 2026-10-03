import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_link_navigation.dart';
import 'package:y300/features/profile/presentation/profile_action_navigation.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/user_profile_controller.dart';
import 'package:y300/features/profile/presentation/widgets/profile_content.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

export 'user_profile_controller.dart';

class UserProfilePage extends ConsumerWidget {
  const UserProfilePage({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(verifiedProfileOwnerProvider);
    if (owner?.uid == uid) return const MyProfilePage();
    return _ProfilePage(userId: uid);
  }
}

class MyProfilePage extends ConsumerWidget {
  const MyProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(verifiedProfileOwnerProvider);
    return _ProfilePage(userId: owner?.uid, isMyProfile: true);
  }
}

class _ProfilePage extends ConsumerStatefulWidget {
  const _ProfilePage({this.userId, this.isMyProfile = false});
  final String? userId;
  final bool isMyProfile;
  @override
  ConsumerState<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<_ProfilePage> {
  bool _opening = false;

  Future<void> _refresh() => widget.isMyProfile
      ? ref.read(myUserProfileProvider.notifier).refresh()
      : ref.read(userProfileProvider(widget.userId!).notifier).refresh();

  Future<void> _openAction(
    ForumUserProfileActionKind action, {
    ForumUserProfileData? profile,
  }) async {
    if (_opening) return;
    final owner = ref.read(verifiedProfileOwnerProvider);
    final target = widget.userId;
    if (target == null) return;
    bool current() =>
        mounted &&
        widget.userId == target &&
        ref.read(verifiedProfileOwnerProvider) == owner;
    _opening = true;
    try {
      // Replies are a tab of the same native directory advertised by threads.
      final result =
          profile == null || action == ForumUserProfileActionKind.replies
          ? await openProfileNativeAction(
              context: context,
              ref: ref,
              action: action,
              userId: target,
              isMyProfile: widget.isMyProfile,
              isCurrentOwner: current,
              displayName: profile?.identity.displayName,
            )
          : await openProfileAction(
              context: context,
              ref: ref,
              action: action,
              profile: profile,
              isMyProfile: widget.isMyProfile,
              isCurrentOwner: current,
            );
      // A web visit may change profile fields; verify them with a fresh read.
      if (current() && (result == true || profileActionUsesWeb(action))) {
        await _refresh();
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _openForumPage() async {
    if (_opening) return;
    final owner = ref.read(verifiedProfileOwnerProvider);
    final target = widget.userId;
    if (target == null) return;
    _opening = true;
    try {
      await openProfileForumPage(
        context: context,
        ref: ref,
        userId: target,
        isMyProfile: widget.isMyProfile,
        isCurrentOwner: () =>
            mounted &&
            widget.userId == target &&
            ref.read(verifiedProfileOwnerProvider) == owner,
      );
    } finally {
      _opening = false;
    }
  }

  Future<void> _copyUid(String uid) async {
    await Clipboard.setData(ClipboardData(text: uid));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).profileUidCopied)),
      );
    }
  }

  void _openLink(String url) {
    unawaited(openBlogContentLink(context, ref, url));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).y300NativeContent;
    final owner = ref.watch(verifiedProfileOwnerProvider);
    final asyncProfile = widget.isMyProfile
        ? ref.watch(myUserProfileProvider)
        : ref.watch(userProfileProvider(widget.userId!));
    // AsyncValue may retain an old frame while its owner dependency rebuilds.
    final raw = asyncProfile.asData?.value;
    final state = raw?.belongsToSession(owner) == true ? raw : null;
    final profile = state?.data;
    final waitingForOwner =
        widget.isMyProfile &&
        owner == null &&
        (ref.watch(authSessionControllerProvider).isLoading ||
            ref.watch(profileSessionRevisionProvider).isLoading);
    final unauthorized =
        widget.isMyProfile &&
        state?.failure?.kind == DataReadFailureKind.unauthorized;
    final title = widget.isMyProfile
        ? l10n.profileMyTitle
        : profile?.identity.displayName?.isNotEmpty == true
        ? l10n.profileUserTitle(profile!.identity.displayName!)
        : l10n.profileTitle;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.userId != null)
            IconButton(
              key: const Key('user-profile-open-web'),
              tooltip: l10n.profileOpenForumPage,
              onPressed: _openForumPage,
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          IconButton(
            tooltip: l10n.profileHome,
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: widget.isMyProfile && owner == null
          ? waitingForOwner
                ? const Center(child: CircularProgressIndicator())
                : _ProfileStatus(
                    message: l10n.profileLoginRequired,
                    icon: Icons.person_outline_rounded,
                    actionLabel: l10n.moreLogin,
                    onAction: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    ),
                  )
          : profile != null
          ? RefreshIndicator(
              onRefresh: _refresh,
              child: ProfileContent(
                profile: profile,
                capabilities: state?.capabilities,
                imageReferer: ref.watch(forumImageRefererProvider),
                isMyProfile: widget.isMyProfile,
                canInteract: owner != null,
                onLogin: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                ),
                isRefreshing: state?.isRefreshing == true,
                failureText: state?.failure == null
                    ? null
                    : _errorText(l10n, state!.failure),
                onAction: (action) =>
                    unawaited(_openAction(action, profile: profile)),
                onOpenLink: _openLink,
                onCopyUid: () => unawaited(_copyUid(profile.identity.userId)),
              ),
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (asyncProfile.isLoading ||
                    (state == null && !asyncProfile.hasError))
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _ProfileStatus(
                    message: unauthorized
                        ? l10n.profileLoginRequired
                        : _errorText(
                            l10n,
                            state?.failure ?? asyncProfile.error,
                          ),
                    icon: Icons.person_search_outlined,
                    actionLabel: l10n.commonRetry,
                    onAction: () async {
                      if (unauthorized) {
                        await ref
                            .read(authSessionControllerProvider.notifier)
                            .refresh();
                        if (mounted) ref.invalidate(myUserProfileProvider);
                      } else {
                        await _refresh();
                      }
                    },
                    onOpenForumPage:
                        state?.failure?.kind == DataReadFailureKind.parse ||
                            state?.failure?.kind ==
                                DataReadFailureKind.unsupported
                        ? _openForumPage
                        : null,
                    isMyProfile: widget.isMyProfile,
                  ),
                if (widget.isMyProfile && owner != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    l10n.profileMyContent,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  ProfileActionTiles(
                    key: const Key('my-profile-native-shortcuts'),
                    actions: const [
                      ForumUserProfileActionKind.threads,
                      ForumUserProfileActionKind.replies,
                      ForumUserProfileActionKind.blogs,
                      ForumUserProfileActionKind.messages,
                    ],
                    isMyProfile: true,
                    compact: true,
                    onAction: (action) => unawaited(_openAction(action)),
                  ),
                ],
              ],
            ),
    );
  }
}

String _errorText(AppLocalizations l10n, Object? error) =>
    l10n.profileLoadFailed(LocalizedErrorSummary.resolve(l10n, error));

class _ProfileStatus extends StatelessWidget {
  const _ProfileStatus({
    required this.message,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    this.onOpenForumPage,
    this.isMyProfile = false,
  });
  final String message;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onOpenForumPage;
  final bool isMyProfile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).y300NativeContent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: colors.accent),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.body),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
              if (onOpenForumPage != null)
                OutlinedButton(
                  key: Key(
                    isMyProfile
                        ? 'my-profile-open-forum-page'
                        : 'user-profile-fallback-web',
                  ),
                  onPressed: onOpenForumPage,
                  child: Text(
                    AppLocalizations.of(context).profileOpenForumPage,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
