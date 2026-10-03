import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/profile/presentation/widgets/profile_contact_actions.dart';
import 'package:y300/features/profile/presentation/widgets/profile_identity_card.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Profile composition stays independent of repositories and route ownership.
class ProfileContent extends StatelessWidget {
  const ProfileContent({
    super.key,
    required this.profile,
    required this.capabilities,
    required this.imageReferer,
    required this.isMyProfile,
    required this.onAction,
    required this.onOpenLink,
    required this.onCopyUid,
    this.isRefreshing = false,
    this.failureText,
    this.canInteract = true,
    this.onLogin,
  });

  final ForumUserProfileData profile;
  final ForumUserProfileReadCapabilities? capabilities;
  final String imageReferer;
  final bool isMyProfile;
  final ValueChanged<ForumUserProfileActionKind> onAction;
  final ValueChanged<String> onOpenLink;
  final VoidCallback onCopyUid;
  final bool isRefreshing;
  final String? failureText;
  final bool canInteract;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).y300NativeContent;
    bool supports(ForumUserProfileCapability capability) =>
        capabilities?.supports(capability) == true;
    final actions = supports(ForumUserProfileCapability.orderedActions)
        ? profile.actions.toSet()
        : <ForumUserProfileActionKind>{};
    final contentActions = [
      if (actions.contains(ForumUserProfileActionKind.threads))
        ForumUserProfileActionKind.threads,
      // The native thread directory exposes both tabs through one read contract.
      if (actions.contains(ForumUserProfileActionKind.threads) ||
          actions.contains(ForumUserProfileActionKind.replies))
        ForumUserProfileActionKind.replies,
      if (actions.contains(ForumUserProfileActionKind.blogs))
        ForumUserProfileActionKind.blogs,
    ];
    final tools = [
      for (final kind in [
        ForumUserProfileActionKind.messages,
        ForumUserProfileActionKind.forumFavorites,
        ForumUserProfileActionKind.friends,
        ForumUserProfileActionKind.creditHistory,
      ])
        if (isMyProfile && actions.contains(kind)) kind,
    ];
    VoidCallback? contactAction(ForumUserProfileActionKind kind) =>
        !isMyProfile && canInteract && actions.contains(kind)
        ? () => onAction(kind)
        : null;
    final onSendMessage = contactAction(ForumUserProfileActionKind.sendMessage);
    final onAddFriend = contactAction(ForumUserProfileActionKind.addFriend);
    final onRemoveFriend = contactAction(
      ForumUserProfileActionKind.removeFriend,
    );
    final hasSignature =
        supports(ForumUserProfileCapability.signatureMarkup) &&
        profile.signatureHtml?.trim().isNotEmpty == true;
    final details = supports(ForumUserProfileCapability.orderedDetails)
        ? profile.details
              .where((entry) => entry.value.trim().isNotEmpty)
              .toList()
        : <ForumUserProfileDetail>[];
    final metrics = supports(ForumUserProfileCapability.orderedMetrics)
        ? profile.metrics
        : <ForumUserProfileMetric>[];
    final additionalMetrics = metrics.skip(3).toList(growable: false);

    return ListView(
      key: const Key('user-profile-page-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isRefreshing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(
                      key: Key('user-profile-refresh-progress'),
                    ),
                  ),
                if (failureText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      failureText!,
                      style: TextStyle(color: colors.supportingText),
                    ),
                  ),
                ProfileIdentityCard(
                  profile: profile,
                  metrics: metrics.take(3).toList(growable: false),
                  avatarUrl:
                      supports(ForumUserProfileCapability.avatarReference)
                      ? profile.avatarUrl
                      : null,
                  imageReferer: imageReferer,
                  onCopyUid: onCopyUid,
                  footer:
                      onSendMessage != null ||
                          onAddFriend != null ||
                          onRemoveFriend != null
                      ? ProfileContactActions(
                          onSendMessage: onSendMessage,
                          onAddFriend: onAddFriend,
                          onRemoveFriend: onRemoveFriend,
                        )
                      : null,
                ),
                if (!isMyProfile && !canInteract && onLogin != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const Key('user-profile-login'),
                    onPressed: onLogin,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text(l10n.profileLoginToInteract),
                  ),
                ],
                if (contentActions.isNotEmpty || tools.isNotEmpty)
                  Column(
                    key: const Key('user-profile-actions'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (contentActions.isNotEmpty) ...[
                        _SectionHeading(
                          title: isMyProfile
                              ? l10n.profileMyContent
                              : l10n.profileUserContent,
                        ),
                        ProfileActionTiles(
                          actions: contentActions,
                          isMyProfile: isMyProfile,
                          onAction: onAction,
                          compact: true,
                        ),
                      ],
                      if (tools.isNotEmpty) ...[
                        _SectionHeading(title: l10n.profileAccountTools),
                        ProfileActionTiles(
                          actions: tools,
                          isMyProfile: isMyProfile,
                          onAction: onAction,
                        ),
                      ],
                    ],
                  ),
                if (hasSignature) ...[
                  _SectionHeading(title: l10n.profileSignature),
                  ProfileSurface(
                    key: const Key('user-profile-signature'),
                    child: ForumHtmlContentView(
                      html: profile.signatureHtml!,
                      sourceId:
                          'user-profile-signature-${profile.identity.userId}',
                      imageCacheOwnerId: profile.identity.userId,
                      imageReferer: imageReferer,
                      surfaceColor: colors.card,
                      foregroundColor: colors.body,
                      onOpenLink: onOpenLink,
                    ),
                  ),
                ],
                if (additionalMetrics.isNotEmpty) ...[
                  _SectionHeading(title: l10n.profileCreditOverview),
                  _Metrics(metrics: additionalMetrics),
                ],
                if (details.isNotEmpty)
                  Column(
                    key: const Key('user-profile-details'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionHeading(title: l10n.profileDetails),
                      _Details(details: details, onOpenLink: onOpenLink),
                    ],
                  ),
                if (metrics.isEmpty &&
                    !hasSignature &&
                    !details.any((entry) => entry.label.toLowerCase() != 'uid'))
                  Padding(
                    key: const Key('user-profile-empty-details'),
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      l10n.profileNoAdditionalDetails,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.supportingText),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ProfileActionTiles extends StatelessWidget {
  const ProfileActionTiles({
    super.key,
    required this.actions,
    required this.isMyProfile,
    required this.onAction,
    this.compact = false,
  });

  final List<ForumUserProfileActionKind> actions;
  final bool isMyProfile;
  final ValueChanged<ForumUserProfileActionKind> onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).y300NativeContent;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = compact
            ? (constraints.maxWidth >= 320 && scale < 1.4
                  ? 3
                  : constraints.maxWidth >= 260 && scale < 1.7
                  ? 2
                  : 1)
            : (constraints.maxWidth >= 480 && scale < 1.5 ? 2 : 1);
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: Material(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('user-profile-action-${action.name}'),
                    onTap: () => onAction(action),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 16 : 14),
                      child: compact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ActionIcon(action: action),
                                const SizedBox(height: 14),
                                Text(
                                  profileActionLabel(
                                    context,
                                    action,
                                    isMyProfile: isMyProfile,
                                  ),
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: colors.itemTitle,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                _ActionIcon(action: action),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    profileActionLabel(
                                      context,
                                      action,
                                      isMyProfile: isMyProfile,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: colors.itemTitle,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  profileActionUsesWeb(action)
                                      ? Icons.open_in_new_rounded
                                      : Icons.chevron_right_rounded,
                                  size: 17,
                                  color: colors.supportingText,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.action});
  final ForumUserProfileActionKind action;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).y300NativeContent;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.panelBackground,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(profileActionIcon(action), size: 20, color: colors.accent),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.metrics});
  final List<ForumUserProfileMetric> metrics;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).y300NativeContent;
    return ProfileSurface(
      key: const Key('user-profile-additional-metrics'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final columns = constraints.maxWidth >= 280 && scale < 1.4
              ? 3
              : constraints.maxWidth >= 200 && scale < 1.8
              ? 2
              : 1;
          final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
          return Wrap(
            spacing: 16,
            runSpacing: 20,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colors.itemTitle,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        metric.label,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.supportingText),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.details, required this.onOpenLink});
  final List<ForumUserProfileDetail> details;
  final ValueChanged<String> onOpenLink;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).y300NativeContent;
    return ProfileSurface(
      child: Column(
        children: [
          for (var index = 0; index < details.length; index++) ...[
            if (index > 0)
              Divider(height: 24, color: colors.accent.withValues(alpha: 0.08)),
            LayoutBuilder(
              builder: (context, constraints) {
                final detail = details[index];
                final uri = Uri.tryParse(detail.value);
                final hasLink =
                    uri != null &&
                    {'https', 'http'}.contains(uri.scheme) &&
                    uri.host.isNotEmpty &&
                    uri.userInfo.isEmpty;
                final value = SelectableText(
                  detail.value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: hasLink ? colors.accent : colors.body,
                    height: 1.5,
                  ),
                  onTap: hasLink ? () => onOpenLink(detail.value) : null,
                );
                final label = Text(
                  detail.label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.supportingText),
                );
                if (MediaQuery.textScalerOf(context).scale(14) > 22 ||
                    constraints.maxWidth < 240) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [label, const SizedBox(height: 6), value],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: constraints.maxWidth * 0.32, child: label),
                    const SizedBox(width: 12),
                    Expanded(child: value),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 24, 2, 12),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).y300NativeContent.itemTitle,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class ProfileSurface extends StatelessWidget {
  const ProfileSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).y300NativeContent.card,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

String profileActionLabel(
  BuildContext context,
  ForumUserProfileActionKind kind, {
  bool isMyProfile = false,
}) {
  final l10n = AppLocalizations.of(context);
  return switch (kind) {
    ForumUserProfileActionKind.threads =>
      isMyProfile ? l10n.profileMyThreads : l10n.profileMyThreadsTab,
    ForumUserProfileActionKind.replies =>
      isMyProfile ? l10n.profileMyReplies : l10n.profileMyRepliesTab,
    ForumUserProfileActionKind.blogs =>
      isMyProfile ? l10n.profileMyBlogs : l10n.profileBlogTitle,
    ForumUserProfileActionKind.messages => l10n.profileMessages,
    ForumUserProfileActionKind.sendMessage => l10n.profileSendMessage,
    ForumUserProfileActionKind.addFriend => l10n.profileAddFriend,
    ForumUserProfileActionKind.removeFriend => l10n.profileRemoveFriend,
    ForumUserProfileActionKind.forumFavorites => l10n.profileForumFavorites,
    ForumUserProfileActionKind.friends => l10n.profileFriends,
    ForumUserProfileActionKind.settings => l10n.profileSettings,
    ForumUserProfileActionKind.creditHistory => l10n.profileCreditHistory,
  };
}

IconData profileActionIcon(ForumUserProfileActionKind kind) => switch (kind) {
  ForumUserProfileActionKind.threads => Icons.forum_outlined,
  ForumUserProfileActionKind.replies => Icons.chat_outlined,
  ForumUserProfileActionKind.blogs => Icons.auto_stories_outlined,
  ForumUserProfileActionKind.messages ||
  ForumUserProfileActionKind.sendMessage => Icons.mail_outline_rounded,
  ForumUserProfileActionKind.addFriend => Icons.person_add_alt_outlined,
  ForumUserProfileActionKind.removeFriend => Icons.person_remove_outlined,
  ForumUserProfileActionKind.forumFavorites => Icons.bookmarks_outlined,
  ForumUserProfileActionKind.friends => Icons.people_outline_rounded,
  ForumUserProfileActionKind.settings => Icons.settings_outlined,
  ForumUserProfileActionKind.creditHistory => Icons.receipt_long_outlined,
};

bool profileActionUsesWeb(ForumUserProfileActionKind kind) => switch (kind) {
  ForumUserProfileActionKind.forumFavorites ||
  ForumUserProfileActionKind.friends ||
  ForumUserProfileActionKind.settings ||
  ForumUserProfileActionKind.creditHistory => true,
  _ => false,
};
