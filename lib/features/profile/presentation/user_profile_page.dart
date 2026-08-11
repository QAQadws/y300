import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/profile/data/repositories/profile_repository.dart';
import 'package:y300/features/profile/data/models/profile_blog_models.dart';
import 'package:y300/features/profile/data/models/user_profile_models.dart';
import 'package:y300/features/profile/data/repositories/user_profile_repository.dart';
import 'package:y300/features/profile/presentation/my_message_center_page.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

final userProfileProvider = FutureProvider.autoDispose
    .family<UserProfileData, String>((ref, uid) async {
      final result = await ref
          .watch(userProfileRepositoryProvider)
          .getUserProfile(uid: uid);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

final myUserProfileProvider = FutureProvider.autoDispose<UserProfileData>((
  ref,
) async {
  final uid = await _resolveCurrentUid(ref);
  final result = await ref
      .watch(userProfileRepositoryProvider)
      .getMyProfile(uid: uid);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

Future<String> _resolveCurrentUid(Ref ref) async {
  final sessionUid = ref
      .read(yamiboSessionStoreProvider)
      .readCurrent()
      ?.uid
      .trim();
  if (sessionUid != null && sessionUid.isNotEmpty && sessionUid != '0') {
    return sessionUid;
  }

  final authSession = await ref.read(authSessionControllerProvider.future);
  final authUid = authSession.uid.trim();
  if (authUid.isNotEmpty && authUid != '0') {
    return authUid;
  }

  final profileResult = await ref.read(profileRepositoryProvider).getProfile();
  return switch (profileResult) {
    ApiSuccess(:final data)
        when data.uid.trim().isNotEmpty && data.uid.trim() != '0' =>
      data.uid.trim(),
    ApiSuccess() => throw const ApiError(
      type: ApiErrorType.business,
      message: 'auth.current_user_uid_missing',
    ),
    ApiFailure(:final error) => throw error,
  };
}

class UserProfilePage extends ConsumerWidget {
  const UserProfilePage({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(userProfileProvider(uid));
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);
    final palette = _UserProfilePalette.resolve(Theme.of(context));
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(_profilePageTitle(l10n, asyncProfile.value)),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).profileHome,
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: asyncProfile.when(
        data: (profile) => _UserProfileContent(
          profile: profile,
          palette: palette,
          imageHeaderBuilder: imageHeaderBuilder,
          isMyProfile: false,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _UserProfileError(
          error: error,
          palette: palette,
          onRetry: () => ref.invalidate(userProfileProvider(uid)),
        ),
      ),
    );
  }
}

class MyProfilePage extends ConsumerWidget {
  const MyProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(myUserProfileProvider);
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);
    final palette = _UserProfilePalette.resolve(Theme.of(context));
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(
          _profilePageTitle(l10n, asyncProfile.value, isMyProfile: true),
        ),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).profileHome,
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: asyncProfile.when(
        data: (profile) => _UserProfileContent(
          profile: profile,
          palette: palette,
          imageHeaderBuilder: imageHeaderBuilder,
          isMyProfile: true,
          onOpenMessages: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MyMessageCenterPage(),
              ),
            );
          },
          onOpenBlogs: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const ProfileBlogPage(initialView: ProfileBlogView.mine),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _UserProfileError(
          error: error,
          palette: palette,
          onRetry: () => ref.invalidate(myUserProfileProvider),
        ),
      ),
    );
  }
}

class _UserProfileContent extends StatelessWidget {
  const _UserProfileContent({
    required this.profile,
    required this.palette,
    required this.imageHeaderBuilder,
    required this.isMyProfile,
    this.onOpenMessages,
    this.onOpenBlogs,
  });

  final UserProfileData profile;
  final _UserProfilePalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;
  final bool isMyProfile;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenBlogs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('user-profile-page-list'),
      padding: EdgeInsets.zero,
      children: [
        _UserProfileHero(
          profile: profile,
          palette: palette,
          imageHeaderBuilder: imageHeaderBuilder,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Transform.translate(
                offset: const Offset(0, -30),
                child: _MetricCard(profile: profile, palette: palette),
              ),
              Transform.translate(
                offset: const Offset(0, -18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ActionGrid(
                      profile: profile,
                      palette: palette,
                      isMyProfile: isMyProfile,
                      onOpenMessages: onOpenMessages,
                      onOpenBlogs: onOpenBlogs,
                    ),
                    if (profile.signatureHtml?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      _SignatureSection(
                        profile: profile,
                        palette: palette,
                        imageHeaderBuilder: imageHeaderBuilder,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _DetailsSection(profile: profile, palette: palette),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserProfileHero extends StatelessWidget {
  const _UserProfileHero({
    required this.profile,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  final UserProfileData profile;
  final _UserProfilePalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    final coverUrl = profile.coverUrl?.trim();
    final avatarUrl = profile.avatarUrl?.trim();
    return Container(
      height: 244,
      decoration: BoxDecoration(color: palette.heroFallback),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverUrl != null && coverUrl.isNotEmpty)
            LibraryCachedImage(
              imageUrl: coverUrl,
              fit: BoxFit.cover,
              placeholder: const SizedBox.expand(),
              headerBuilder: imageHeaderBuilder,
            ),
          Container(color: Colors.black.withValues(alpha: 0.42)),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: palette.card,
                child: ForumCachedAvatar(
                  key: const Key('user-profile-avatar'),
                  imageUrl: avatarUrl,
                  ownerId: profile.uid.trim().isEmpty
                      ? profile.username
                      : profile.uid,
                  ownerType: ImageCacheOwnerType.profile,
                  size: 68,
                  placeholder: Icon(Icons.person, color: palette.accent),
                  headerBuilder: imageHeaderBuilder,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                profile.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.profile, required this.palette});

  final UserProfileData profile;
  final _UserProfilePalette palette;

  @override
  Widget build(BuildContext context) {
    final metrics = profile.credits;
    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('user-profile-metrics'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: _cardDecoration(palette),
      child: Row(
        children: [
          for (final metric in metrics)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    metric.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: palette.title,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metric.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: palette.muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.profile,
    required this.palette,
    required this.isMyProfile,
    this.onOpenMessages,
    this.onOpenBlogs,
  });

  final UserProfileData profile;
  final _UserProfilePalette palette;
  final bool isMyProfile;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenBlogs;

  @override
  Widget build(BuildContext context) {
    final actions = _buildActions(context);
    return Container(
      key: const Key('user-profile-actions'),
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(palette),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: actions.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 3.6,
        ),
        itemBuilder: (context, index) {
          final action = actions[index];
          return _ActionTile(action: action, palette: palette);
        },
      ),
    );
  }

  List<_ProfileAction> _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (profile.actions.isNotEmpty) {
      return [for (final action in profile.actions) _fromServerAction(action)];
    }
    if (isMyProfile) {
      return <_ProfileAction>[
        _ProfileAction(
          l10n.profileMyThreads,
          Icons.chat_bubble,
          profile.threadUrl,
        ),
        _ProfileAction(
          l10n.profileMyBlogs,
          Icons.sms,
          profile.blogUrl,
          onTap: onOpenBlogs,
        ),
        _ProfileAction(
          l10n.profileMyFavorites,
          Icons.star,
          profile.favoriteUrl,
        ),
        _ProfileAction(
          l10n.profileMessages,
          Icons.notifications,
          profile.messageUrl,
          onTap: onOpenMessages,
        ),
        _ProfileAction(
          l10n.profileMyFriends,
          Icons.people_alt,
          profile.friendUrl,
        ),
        _ProfileAction(
          l10n.profileDailyCheckIn,
          Icons.edit_note,
          profile.signUrl,
        ),
      ];
    }
    return <_ProfileAction>[
      _ProfileAction(
        l10n.profileTheirThreads,
        Icons.chat_bubble,
        profile.threadUrl,
      ),
      _ProfileAction(l10n.profileTheirBlogs, Icons.sms, profile.blogUrl),
      _ProfileAction(
        l10n.profileSendMessage,
        Icons.message,
        profile.messageUrl,
      ),
      _ProfileAction(
        l10n.profileAddFriend,
        Icons.person_add_alt_1,
        profile.friendUrl,
      ),
    ];
  }

  _ProfileAction _fromServerAction(UserProfileAction action) {
    final kind = _profileActionKind(action.url);
    return _ProfileAction(
      action.label,
      kind.icon,
      action.url,
      onTap: isMyProfile && kind == _ProfileActionKind.messages
          ? onOpenMessages
          : isMyProfile && kind == _ProfileActionKind.blogs
          ? onOpenBlogs
          : null,
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.palette});

  final _ProfileAction action;
  final _UserProfilePalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.actionBackground,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap:
            action.onTap ??
            (action.url == null
                ? null
                : () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context).profileActionUnavailable,
                      ),
                    ),
                  )),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: palette.actionIconBackground,
                child: Icon(action.icon, size: 17, color: palette.onAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.title,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignatureSection extends StatelessWidget {
  const _SignatureSection({
    required this.profile,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  final UserProfileData profile;
  final _UserProfilePalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      key: const Key('user-profile-signature'),
      title: AppLocalizations.of(context).profileSignature,
      palette: palette,
      child: DefaultTextStyle.merge(
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: palette.body, height: 1.45),
        child: ForumHtmlContentView(
          html: profile.signatureHtml ?? '',
          sourceId: 'user-profile-signature-${profile.uid}',
          imageCacheOwnerId: profile.uid.trim().isEmpty
              ? profile.username
              : profile.uid,
          imageHeaderBuilder: imageHeaderBuilder,
          surfaceColor: palette.card,
          foregroundColor: palette.body,
          onOpenLink: (url) => ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(url))),
        ),
      ),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.profile, required this.palette});

  final UserProfileData profile;
  final _UserProfilePalette palette;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      key: const Key('user-profile-details'),
      title: AppLocalizations.of(context).profileDetails,
      palette: palette,
      child: Column(
        children: [
          for (final detail in profile.details)
            _DetailRow(detail: detail, palette: palette),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.title,
    required this.palette,
    required this.child,
  });

  final String title;
  final _UserProfilePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: _cardDecoration(palette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.title,
              fontWeight: FontWeight.w800,
            ),
          ),
          Divider(height: 22, color: palette.border),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail, required this.palette});

  final UserProfileDetailItem detail;
  final _UserProfilePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.body,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              detail.value,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserProfileError extends StatelessWidget {
  const _UserProfileError({
    required this.error,
    required this.palette,
    required this.onRetry,
  });

  final Object error;
  final _UserProfilePalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: palette.accent, size: 34),
            const SizedBox(height: 12),
            Text(
              _profileErrorText(context, error),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.body),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAction {
  const _ProfileAction(this.label, this.icon, this.url, {this.onTap});

  final String label;
  final IconData icon;
  final String? url;
  final VoidCallback? onTap;
}

enum _ProfileActionKind {
  threads(Icons.chat_bubble),
  blogs(Icons.sms),
  favorites(Icons.star),
  messages(Icons.notifications),
  friends(Icons.people_alt),
  checkIn(Icons.edit_note),
  other(Icons.chevron_right);

  const _ProfileActionKind(this.icon);

  final IconData icon;
}

_ProfileActionKind _profileActionKind(String? rawUrl) {
  final uri = Uri.tryParse(rawUrl?.trim() ?? '');
  if (uri == null) {
    return _ProfileActionKind.other;
  }
  final query = uri.queryParameters;
  return switch (query['do']) {
    'thread' => _ProfileActionKind.threads,
    'blog' => _ProfileActionKind.blogs,
    'favorite' => _ProfileActionKind.favorites,
    'pm' => _ProfileActionKind.messages,
    _ when query['ac'] == 'friend' => _ProfileActionKind.friends,
    _
        when uri.path.endsWith('/plugin.php') &&
            query['id']?.startsWith('zqlj_sign') == true =>
      _ProfileActionKind.checkIn,
    _ => _ProfileActionKind.other,
  };
}

String _profileErrorText(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  if (error case ApiError(message: 'auth.current_user_uid_missing')) {
    return l10n.profileLoginRequired;
  }
  return l10n.profileLoadFailed(LocalizedErrorSummary.resolve(l10n, error));
}

String _profilePageTitle(
  AppLocalizations l10n,
  UserProfileData? profile, {
  bool isMyProfile = false,
}) {
  final rawTitle = profile?.title.trim();
  if (rawTitle?.isNotEmpty == true) {
    return profile!.title;
  }
  if (isMyProfile) {
    return l10n.profileMyTitle;
  }
  final username = profile?.username.trim();
  return username?.isNotEmpty == true
      ? l10n.profileUserTitle(username!)
      : l10n.profileTitle;
}

@immutable
class _UserProfilePalette {
  const _UserProfilePalette({
    required this.background,
    required this.card,
    required this.actionBackground,
    required this.heroFallback,
    required this.accent,
    required this.onAccent,
    required this.title,
    required this.body,
    required this.muted,
    required this.border,
    required this.actionIconBackground,
  });

  final Color background;
  final Color card;
  final Color actionBackground;
  final Color heroFallback;
  final Color accent;
  final Color onAccent;
  final Color title;
  final Color body;
  final Color muted;
  final Color border;
  final Color actionIconBackground;

  static _UserProfilePalette resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final appBarBackground =
        theme.appBarTheme.backgroundColor ?? scheme.primary;
    final appBarForeground =
        theme.appBarTheme.foregroundColor ?? scheme.onPrimary;
    final native = theme.y300NativeContent;
    if (isDark) {
      return _UserProfilePalette(
        background: theme.scaffoldBackgroundColor,
        card: scheme.surfaceContainer,
        actionBackground: scheme.surfaceContainerHighest,
        heroFallback: scheme.surfaceContainerHighest,
        accent: appBarBackground,
        onAccent: appBarForeground,
        title: scheme.onSurface,
        body: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        border: scheme.outlineVariant.withValues(alpha: 0.42),
        actionIconBackground: scheme.primary,
      );
    }
    return _UserProfilePalette(
      background: native.background,
      card: native.card,
      actionBackground: native.translucentSurface,
      heroFallback: native.accent,
      accent: appBarBackground,
      onAccent: appBarForeground,
      title: native.title,
      body: native.body,
      muted: native.tertiaryText,
      border: native.accent.withValues(alpha: 0.10),
      actionIconBackground: appBarBackground,
    );
  }
}

BoxDecoration _cardDecoration(_UserProfilePalette palette) {
  return BoxDecoration(
    color: palette.card,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: palette.border),
  );
}
