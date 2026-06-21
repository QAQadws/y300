import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/profile/data/models/user_profile_models.dart';
import 'package:y300/features/profile/data/user_profile_repository.dart';
import 'package:y300/features/profile/presentation/my_message_center_page.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';

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
      message: '当前用户 UID 缺失，请先登录',
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

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(asyncProfile.value?.title ?? '个人资料'),
        actions: [
          IconButton(
            tooltip: '首页',
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

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(asyncProfile.value?.title ?? '我的资料'),
        actions: [
          IconButton(
            tooltip: '首页',
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
  });

  final UserProfileData profile;
  final _UserProfilePalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;
  final bool isMyProfile;
  final VoidCallback? onOpenMessages;

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
                child: ClipOval(
                  child: avatarUrl == null || avatarUrl.isEmpty
                      ? Icon(Icons.person, color: palette.accent, size: 36)
                      : Image.network(
                          avatarUrl,
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(Icons.person, color: palette.accent),
                        ),
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
  });

  final UserProfileData profile;
  final _UserProfilePalette palette;
  final bool isMyProfile;
  final VoidCallback? onOpenMessages;

  @override
  Widget build(BuildContext context) {
    final actions = _buildActions();
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

  List<_ProfileAction> _buildActions() {
    if (profile.actions.isNotEmpty) {
      return [
        for (final action in profile.actions)
          _ProfileAction(
            action.label,
            _iconForActionLabel(action.label),
            action.url,
            onTap: isMyProfile && action.label.contains('消息')
                ? onOpenMessages
                : null,
          ),
      ];
    }
    if (isMyProfile) {
      return <_ProfileAction>[
        _ProfileAction('我的主题', Icons.chat_bubble, profile.threadUrl),
        _ProfileAction('我的日志', Icons.sms, profile.blogUrl),
        _ProfileAction('我的收藏', Icons.star, profile.favoriteUrl),
        _ProfileAction(
          '消息提醒',
          Icons.notifications,
          profile.messageUrl,
          onTap: onOpenMessages,
        ),
        _ProfileAction('我的好友', Icons.people_alt, profile.friendUrl),
        _ProfileAction('每日签到', Icons.edit_note, profile.signUrl),
      ];
    }
    return <_ProfileAction>[
      _ProfileAction('Ta的主题', Icons.chat_bubble, profile.threadUrl),
      _ProfileAction('Ta的日志', Icons.sms, profile.blogUrl),
      _ProfileAction('发短消息', Icons.message, profile.messageUrl),
      _ProfileAction('加为好友', Icons.person_add_alt_1, profile.friendUrl),
    ];
  }

  IconData _iconForActionLabel(String label) {
    if (label.contains('主题')) {
      return Icons.chat_bubble;
    }
    if (label.contains('日志')) {
      return Icons.sms;
    }
    if (label.contains('收藏')) {
      return Icons.star;
    }
    if (label.contains('消息') || label.contains('短消息')) {
      return Icons.notifications;
    }
    if (label.contains('好友')) {
      return Icons.people_alt;
    }
    if (label.contains('签到')) {
      return Icons.edit_note;
    }
    return Icons.chevron_right;
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
                : () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('暂未接入该操作')))),
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
      title: '个人签名',
      palette: palette,
      child: DefaultTextStyle.merge(
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: palette.body, height: 1.45),
        child: ThreadPostHtml(
          data: profile.signatureHtml ?? '',
          imageHeaderBuilder: imageHeaderBuilder,
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
      title: '个人资料',
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
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.body),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
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
      background: AppThemeTokens.scaffoldBackground,
      card: AppThemeTokens.forumWebviewSectionBackground,
      actionBackground: Colors.white.withValues(alpha: 0.68),
      heroFallback: AppThemeTokens.appBarBackground,
      accent: appBarBackground,
      onAccent: appBarForeground,
      title: AppThemeTokens.appBarBackground,
      body: const Color(0xFF4F3A2A),
      muted: const Color(0xFF9A8E82),
      border: AppThemeTokens.appBarBackground.withValues(alpha: 0.10),
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
