import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/my_message_center_page.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

final class ForumUserProfilePageState {
  const ForumUserProfilePageState({
    this.data,
    this.capabilities,
    this.metadata,
    this.failure,
    this.isRefreshing = false,
  });

  final ForumUserProfileData? data;
  final ForumUserProfileReadCapabilities? capabilities;
  final DataReadMetadata? metadata;
  final DataReadFailure<ForumUserProfileData, ForumUserProfileReadCapabilities>?
  failure;
  final bool isRefreshing;

  ForumUserProfilePageState copyWith({
    ForumUserProfileData? data,
    ForumUserProfileReadCapabilities? capabilities,
    DataReadMetadata? metadata,
    DataReadFailure<ForumUserProfileData, ForumUserProfileReadCapabilities>?
    failure,
    bool? isRefreshing,
    bool clearFailure = false,
  }) {
    return ForumUserProfilePageState(
      data: data ?? this.data,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? this.metadata,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

final userProfileProvider = AsyncNotifierProvider.autoDispose
    .family<UserProfilePageController, ForumUserProfilePageState, String>(
      (uid) => UserProfilePageController(uid),
    );

final myUserProfileProvider =
    AsyncNotifierProvider.autoDispose<
      MyUserProfilePageController,
      ForumUserProfilePageState
    >(MyUserProfilePageController.new);

final class UserProfilePageController
    extends AsyncNotifier<ForumUserProfilePageState> {
  UserProfilePageController(this._userId);

  final String _userId;

  @override
  Future<ForumUserProfilePageState> build() {
    return _load(
      ForumUserProfileQuery(userId: _userId),
      previous: null,
      cachePolicy: CacheLoadPolicy.cacheFirst,
    );
  }

  Future<void> refresh() async {
    final previous = state.value ?? const ForumUserProfilePageState();
    state = AsyncData(
      previous.copyWith(isRefreshing: true, clearFailure: true),
    );
    state = AsyncData(
      await _load(
        ForumUserProfileQuery(userId: _userId),
        previous: previous,
        cachePolicy: CacheLoadPolicy.networkFirst,
      ),
    );
  }

  Future<ForumUserProfilePageState> _load(
    ForumUserProfileQuery query, {
    required ForumUserProfilePageState? previous,
    required CacheLoadPolicy cachePolicy,
  }) async {
    final result = await ref
        .read(forumUserProfileRepositoryProvider)
        .load(query, cachePolicy: cachePolicy);
    return _profileStateFromResult(result, previous: previous);
  }
}

final class MyUserProfilePageController
    extends AsyncNotifier<ForumUserProfilePageState> {
  String? _resolvedUserId;

  @override
  Future<ForumUserProfilePageState> build() async {
    final userId = await _resolveCurrentUid(ref);
    _resolvedUserId = userId;
    return _load(
      userId,
      previous: null,
      cachePolicy: CacheLoadPolicy.cacheFirst,
    );
  }

  Future<void> refresh() async {
    final previous = state.value ?? const ForumUserProfilePageState();
    state = AsyncData(
      previous.copyWith(isRefreshing: true, clearFailure: true),
    );
    final userId = _resolvedUserId ?? await _resolveCurrentUid(ref);
    _resolvedUserId = userId;
    state = AsyncData(
      await _load(
        userId,
        previous: previous,
        cachePolicy: CacheLoadPolicy.networkFirst,
      ),
    );
  }

  Future<ForumUserProfilePageState> _load(
    String userId, {
    required ForumUserProfilePageState? previous,
    required CacheLoadPolicy cachePolicy,
  }) async {
    final result = await ref
        .read(forumUserProfileRepositoryProvider)
        .load(
          ForumUserProfileQuery(
            userId: userId,
            view: ForumUserProfileView.self,
          ),
          cachePolicy: cachePolicy,
        );
    return _profileStateFromResult(result, previous: previous);
  }
}

ForumUserProfilePageState _profileStateFromResult(
  DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>
  result, {
  required ForumUserProfilePageState? previous,
}) {
  if (result case DataReadSuccess<
    ForumUserProfileData,
    ForumUserProfileReadCapabilities
  >(
    :final data,
    :final capabilities,
    :final metadata,
  )) {
    return ForumUserProfilePageState(
      data: data,
      capabilities: capabilities,
      metadata: metadata,
    );
  }
  return (previous ?? const ForumUserProfilePageState()).copyWith(
    failure: result.failureOrNull,
    isRefreshing: false,
  );
}

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

  final profileResult = await ref
      .read(currentUserProfileRepositoryProvider)
      .load(const CurrentUserProfileQuery());
  if (profileResult case DataReadSuccess<
    CurrentUserProfileData,
    CurrentUserProfileReadCapabilities
  >(
    :final data,
  )) {
    return data.identity.userId;
  }
  throw profileResult.failureOrNull!;
}

class UserProfilePage extends ConsumerWidget {
  const UserProfilePage({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(userProfileProvider(uid));
    final pageState = asyncProfile.value;
    final profile = pageState?.data;
    final imageReferer = ref.watch(forumImageRefererProvider);
    final palette = _UserProfilePalette.resolve(Theme.of(context));
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(_profilePageTitle(l10n, profile)),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).profileHome,
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: profile != null
          ? RefreshIndicator(
              onRefresh: ref.read(userProfileProvider(uid).notifier).refresh,
              child: _UserProfileContent(
                profile: profile,
                capabilities: pageState?.capabilities,
                failure: pageState?.failure,
                palette: palette,
                imageReferer: imageReferer,
                isMyProfile: false,
              ),
            )
          : asyncProfile.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _UserProfileError(
              error: pageState?.failure ?? asyncProfile.error,
              palette: palette,
              onRetry: ref.read(userProfileProvider(uid).notifier).refresh,
            ),
    );
  }
}

class MyProfilePage extends ConsumerWidget {
  const MyProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(myUserProfileProvider);
    final pageState = asyncProfile.value;
    final profile = pageState?.data;
    final imageReferer = ref.watch(forumImageRefererProvider);
    final palette = _UserProfilePalette.resolve(Theme.of(context));
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(_profilePageTitle(l10n, profile, isMyProfile: true)),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).profileHome,
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: profile != null
          ? RefreshIndicator(
              onRefresh: ref.read(myUserProfileProvider.notifier).refresh,
              child: _UserProfileContent(
                profile: profile,
                capabilities: pageState?.capabilities,
                failure: pageState?.failure,
                palette: palette,
                imageReferer: imageReferer,
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
                      builder: (_) => const ProfileBlogPage(
                        initialScope: UserBlogFeedScope.self,
                      ),
                    ),
                  );
                },
              ),
            )
          : asyncProfile.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _UserProfileError(
              error: pageState?.failure ?? asyncProfile.error,
              palette: palette,
              onRetry: ref.read(myUserProfileProvider.notifier).refresh,
            ),
    );
  }
}

class _UserProfileContent extends StatelessWidget {
  const _UserProfileContent({
    required this.profile,
    required this.capabilities,
    required this.failure,
    required this.palette,
    required this.imageReferer,
    required this.isMyProfile,
    this.onOpenMessages,
    this.onOpenBlogs,
  }) : assert(
         !isMyProfile || (onOpenMessages != null && onOpenBlogs != null),
         'My profile actions require both navigation callbacks.',
       );

  final ForumUserProfileData profile;
  final ForumUserProfileReadCapabilities? capabilities;
  final Object? failure;
  final _UserProfilePalette palette;
  final String imageReferer;
  final bool isMyProfile;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenBlogs;

  @override
  Widget build(BuildContext context) {
    final showMetrics =
        capabilities?.supports(ForumUserProfileCapability.orderedMetrics) ==
        true;
    final showSignature =
        capabilities?.supports(ForumUserProfileCapability.signatureMarkup) ==
            true &&
        profile.signatureHtml?.trim().isNotEmpty == true;
    final showDetails =
        capabilities?.supports(ForumUserProfileCapability.orderedDetails) ==
        true;
    return ListView(
      key: const Key('user-profile-page-list'),
      padding: EdgeInsets.zero,
      children: [
        if (failure != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _profileErrorText(context, failure),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
          ),
        _UserProfileHero(
          profile: profile,
          capabilities: capabilities,
          palette: palette,
          imageReferer: imageReferer,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showMetrics)
                Transform.translate(
                  offset: const Offset(0, -30),
                  child: _MetricCard(profile: profile, palette: palette),
                ),
              Transform.translate(
                offset: const Offset(0, -18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isMyProfile)
                      _ActionGrid(
                        palette: palette,
                        onOpenMessages: onOpenMessages!,
                        onOpenBlogs: onOpenBlogs!,
                      ),
                    if (showSignature) ...[
                      if (isMyProfile) const SizedBox(height: 12),
                      _SignatureSection(
                        profile: profile,
                        palette: palette,
                        imageReferer: imageReferer,
                      ),
                    ],
                    if (showDetails) ...[
                      if (isMyProfile || showSignature)
                        const SizedBox(height: 12),
                      _DetailsSection(profile: profile, palette: palette),
                    ],
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
    required this.capabilities,
    required this.palette,
    required this.imageReferer,
  });

  final ForumUserProfileData profile;
  final ForumUserProfileReadCapabilities? capabilities;
  final _UserProfilePalette palette;
  final String imageReferer;

  @override
  Widget build(BuildContext context) {
    final coverUrl =
        capabilities?.supports(ForumUserProfileCapability.coverReference) ==
            true
        ? profile.coverUrl?.trim()
        : null;
    final avatarUrl =
        capabilities?.supports(ForumUserProfileCapability.avatarReference) ==
            true
        ? profile.avatarUrl?.trim()
        : null;
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
              referer: imageReferer,
            ),
          Container(color: Colors.black.withValues(alpha: 0.42)),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 72,
                child: Center(
                  child: ForumCachedAvatar(
                    key: const Key('user-profile-avatar'),
                    imageUrl: avatarUrl,
                    ownerId: profile.identity.userId,
                    ownerType: ImageCacheOwnerType.profile,
                    size: 68,
                    imageReferer: imageReferer,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                profile.identity.displayName ?? profile.identity.userId,
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

  final ForumUserProfileData profile;
  final _UserProfilePalette palette;

  @override
  Widget build(BuildContext context) {
    final metrics = profile.metrics;
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
    required this.palette,
    required this.onOpenMessages,
    required this.onOpenBlogs,
  });

  final _UserProfilePalette palette;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenBlogs;

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
    return <_ProfileAction>[
      _ProfileAction(l10n.profileMyBlogs, Icons.sms, onTap: onOpenBlogs),
      _ProfileAction(
        l10n.profileMessages,
        Icons.notifications,
        onTap: onOpenMessages,
      ),
    ];
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
        onTap: action.onTap,
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
    required this.imageReferer,
  });

  final ForumUserProfileData profile;
  final _UserProfilePalette palette;
  final String imageReferer;

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
          sourceId: 'user-profile-signature-${profile.identity.userId}',
          imageCacheOwnerId: profile.identity.userId,
          imageReferer: imageReferer,
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

  final ForumUserProfileData profile;
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

  final ForumUserProfileDetail detail;
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

  final Object? error;
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
  const _ProfileAction(this.label, this.icon, {required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

String _profileErrorText(BuildContext context, Object? error) {
  final l10n = AppLocalizations.of(context);
  return l10n.profileLoadFailed(LocalizedErrorSummary.resolve(l10n, error));
}

String _profilePageTitle(
  AppLocalizations l10n,
  ForumUserProfileData? profile, {
  bool isMyProfile = false,
}) {
  if (isMyProfile) {
    return l10n.profileMyTitle;
  }
  final username = profile?.identity.displayName?.trim();
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
