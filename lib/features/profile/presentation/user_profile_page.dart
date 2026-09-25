import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_page.dart';
import 'package:y300/features/profile/presentation/my_profile_action_navigation.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
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
    this.ownerUid,
    this.ownerRevision,
  });

  final ForumUserProfileData? data;
  final ForumUserProfileReadCapabilities? capabilities;
  final DataReadMetadata? metadata;
  final DataReadFailure<ForumUserProfileData, ForumUserProfileReadCapabilities>?
  failure;
  final bool isRefreshing;
  final String? ownerUid;
  final int? ownerRevision;

  ForumUserProfilePageState copyWith({
    ForumUserProfileData? data,
    ForumUserProfileReadCapabilities? capabilities,
    DataReadMetadata? metadata,
    DataReadFailure<ForumUserProfileData, ForumUserProfileReadCapabilities>?
    failure,
    bool? isRefreshing,
    bool clearFailure = false,
    String? ownerUid,
    int? ownerRevision,
  }) {
    return ForumUserProfilePageState(
      data: data ?? this.data,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? this.metadata,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      ownerUid: ownerUid ?? this.ownerUid,
      ownerRevision: ownerRevision ?? this.ownerRevision,
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
  int _requestGeneration = 0;

  @override
  Future<ForumUserProfilePageState> build() {
    final generation = ++_requestGeneration;
    final owner = ref.watch(verifiedProfileOwnerProvider);
    ref.onDispose(() => _requestGeneration++);
    if (owner == null) return Future.value(const ForumUserProfilePageState());
    return _load(owner, previous: null, generation: generation);
  }

  Future<void> refresh() async {
    final owner = _currentOwner();
    final previous = state.asData?.value;
    if (owner == null ||
        previous == null ||
        previous.ownerUid != owner.uid ||
        previous.ownerRevision != owner.revision ||
        previous.isRefreshing) {
      return;
    }
    final generation = ++_requestGeneration;
    state = AsyncData(
      previous.copyWith(isRefreshing: true, clearFailure: true),
    );
    final next = await _load(owner, previous: previous, generation: generation);
    if (ref.mounted &&
        generation == _requestGeneration &&
        _currentOwner() == owner) {
      state = AsyncData(next);
    }
  }

  VerifiedProfileOwner? _currentOwner() =>
      ref.read(verifiedProfileOwnerProvider);

  Future<ForumUserProfilePageState> _load(
    VerifiedProfileOwner owner, {
    required ForumUserProfilePageState? previous,
    required int generation,
  }) async {
    late final DataReadResult<
      ForumUserProfileData,
      ForumUserProfileReadCapabilities
    >
    result;
    try {
      result = await ref
          .read(forumUserProfileRepositoryProvider)
          .load(
            ForumUserProfileQuery(
              userId: owner.uid,
              view: ForumUserProfileView.self,
            ),
            cachePolicy: CacheLoadPolicy.networkFirst,
          );
    } on Object {
      result = const DataReadFailure(
        kind: DataReadFailureKind.unknown,
        diagnosticMessage: 'self_profile_read_failed',
      );
    }
    if (!ref.mounted ||
        generation != _requestGeneration ||
        _currentOwner() != owner) {
      return const ForumUserProfilePageState();
    }
    if (result
        case DataReadSuccess<
          ForumUserProfileData,
          ForumUserProfileReadCapabilities
        >(
          :final data,
          :final metadata,
        )
        when data.identity.userId == owner.uid &&
            metadata.origin == DataReadOrigin.network &&
            metadata.freshness == DataReadFreshness.current) {
      return _profileStateFromResult(
        result,
        previous: null,
      ).copyWith(ownerUid: owner.uid, ownerRevision: owner.revision);
    }
    final failure =
        result.failureOrNull ??
        const DataReadFailure<
          ForumUserProfileData,
          ForumUserProfileReadCapabilities
        >(
          kind: DataReadFailureKind.parse,
          diagnosticMessage: 'self_profile_identity_or_provenance_unverified',
        );
    final canRetain =
        previous?.ownerUid == owner.uid &&
        previous?.ownerRevision == owner.revision &&
        (failure.kind == DataReadFailureKind.network ||
            failure.kind == DataReadFailureKind.timeout);
    return ForumUserProfilePageState(
      data: canRetain ? previous?.data : null,
      capabilities: canRetain ? previous?.capabilities : null,
      metadata: canRetain ? previous?.metadata : null,
      failure: failure,
      ownerUid: owner.uid,
      ownerRevision: owner.revision,
    );
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
    final auth = ref.watch(authSessionControllerProvider);
    final revision = ref.watch(profileSessionRevisionProvider);
    final owner = ref.watch(verifiedProfileOwnerProvider);
    final asyncProfile = ref.watch(myUserProfileProvider);
    final pageState = asyncProfile.value;
    final profile =
        owner != null &&
            pageState?.ownerUid == owner.uid &&
            pageState?.ownerRevision == owner.revision
        ? pageState?.data
        : null;
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
      // Owner checks precede the cached AsyncValue so a late result cannot
      // reveal a previous account during logout or an account transition.
      body: owner == null
          ? auth.isLoading || revision.isLoading
                ? const Center(child: CircularProgressIndicator())
                : Center(child: Text(l10n.profileLoginRequired))
          : profile != null
          ? RefreshIndicator(
              onRefresh: ref.read(myUserProfileProvider.notifier).refresh,
              child: _UserProfileContent(
                profile: profile,
                capabilities: pageState?.capabilities,
                failure: pageState?.failure,
                isRefreshing: pageState?.isRefreshing == true,
                signInPanel: const DailySignInPanel(),
                palette: palette,
                imageReferer: imageReferer,
                isMyProfile: true,
                onOpenAction: (action) => openMyProfileAction(
                  context: context,
                  ref: ref,
                  action: action,
                  userId: owner.uid,
                  isCurrentOwner: () =>
                      ref.read(verifiedProfileOwnerProvider) == owner,
                ),
              ),
            )
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: DailySignInPanel(),
                ),
                if (asyncProfile.isLoading ||
                    pageState?.ownerUid != owner.uid ||
                    pageState?.ownerRevision != owner.revision)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _UserProfileError(
                    error: pageState?.failure ?? asyncProfile.error,
                    message:
                        pageState?.failure?.kind ==
                            DataReadFailureKind.unauthorized
                        ? l10n.profileLoginRequired
                        : null,
                    palette: palette,
                    onOpenForumPage:
                        pageState?.ownerUid == owner.uid &&
                            pageState?.ownerRevision == owner.revision &&
                            (pageState?.failure?.kind ==
                                    DataReadFailureKind.parse ||
                                pageState?.failure?.kind ==
                                    DataReadFailureKind.unsupported)
                        ? () {
                            final currentOwner = ref.read(
                              verifiedProfileOwnerProvider,
                            );
                            if (currentOwner == null || currentOwner != owner) {
                              return;
                            }
                            openMyProfileForumPage(
                              context: context,
                              ref: ref,
                              userId: currentOwner.uid,
                            );
                          }
                        : null,
                    onRetry: () {
                      if (pageState?.failure?.kind ==
                          DataReadFailureKind.unauthorized) {
                        unawaited(_retryVerifiedMyProfile(context, ref));
                      } else if (asyncProfile.hasError ||
                          pageState?.ownerUid == null) {
                        ref.invalidate(myUserProfileProvider);
                      } else {
                        unawaited(
                          ref.read(myUserProfileProvider.notifier).refresh(),
                        );
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

Future<void> _retryVerifiedMyProfile(
  BuildContext context,
  WidgetRef ref,
) async {
  await ref.read(authSessionControllerProvider.notifier).refresh();
  if (context.mounted) ref.invalidate(myUserProfileProvider);
}

class _UserProfileContent extends StatelessWidget {
  const _UserProfileContent({
    required this.profile,
    required this.capabilities,
    required this.failure,
    required this.palette,
    required this.imageReferer,
    required this.isMyProfile,
    this.isRefreshing = false,
    this.onOpenAction,
    this.signInPanel,
  }) : assert(!isMyProfile || onOpenAction != null);

  final ForumUserProfileData profile;
  final ForumUserProfileReadCapabilities? capabilities;
  final Object? failure;
  final _UserProfilePalette palette;
  final String imageReferer;
  final bool isMyProfile;
  final bool isRefreshing;
  final ValueChanged<ForumUserProfileActionKind>? onOpenAction;
  final Widget? signInPanel;

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
            true &&
        profile.details.any((detail) => detail.value.trim().isNotEmpty);
    final actions =
        isMyProfile &&
            capabilities?.supports(ForumUserProfileCapability.orderedActions) ==
                true
        ? profile.actions
        : const <ForumUserProfileActionKind>[];
    final hasAdditionalDetails =
        (showMetrics && profile.metrics.isNotEmpty) ||
        showSignature ||
        (showDetails &&
            profile.details.any(
              (detail) =>
                  detail.label.trim().toLowerCase() != 'uid' &&
                  detail.value.trim().isNotEmpty,
            ));
    return ListView(
      key: const Key('user-profile-page-list'),
      padding: EdgeInsets.zero,
      children: [
        if (signInPanel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: signInPanel!,
          ),
        if (isRefreshing)
          const LinearProgressIndicator(
            key: Key('user-profile-refresh-progress'),
          ),
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
                    if (actions.isNotEmpty)
                      _ActionGrid(
                        palette: palette,
                        actions: actions,
                        onOpenAction: onOpenAction!,
                      ),
                    if (showSignature) ...[
                      if (actions.isNotEmpty) const SizedBox(height: 12),
                      _SignatureSection(
                        profile: profile,
                        palette: palette,
                        imageReferer: imageReferer,
                      ),
                    ],
                    if (showDetails) ...[
                      if (actions.isNotEmpty || showSignature)
                        const SizedBox(height: 12),
                      _DetailsSection(profile: profile, palette: palette),
                    ],
                    if (!hasAdditionalDetails) ...[
                      if (actions.isNotEmpty || showDetails)
                        const SizedBox(height: 12),
                      _EmptyDetailsCard(palette: palette),
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
    required this.actions,
    required this.onOpenAction,
  });

  final _UserProfilePalette palette;
  final List<ForumUserProfileActionKind> actions;
  final ValueChanged<ForumUserProfileActionKind> onOpenAction;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final kind in actions)
        _ProfileAction(
          kind,
          _labelFor(context, kind),
          _iconFor(kind),
          onTap: () => onOpenAction(kind),
        ),
    ];
    return Container(
      key: const Key('user-profile-actions'),
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(palette),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = constraints.maxWidth >= 420
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final action in tiles)
                SizedBox(
                  width: tileWidth,
                  child: _ActionTile(action: action, palette: palette),
                ),
            ],
          );
        },
      ),
    );
  }

  String _labelFor(BuildContext context, ForumUserProfileActionKind kind) {
    final l10n = AppLocalizations.of(context);
    return switch (kind) {
      ForumUserProfileActionKind.threads => l10n.profileMyThreads,
      ForumUserProfileActionKind.blogs => l10n.profileMyBlogs,
      ForumUserProfileActionKind.forumFavorites => l10n.profileForumFavorites,
      ForumUserProfileActionKind.messages => l10n.profileMessages,
      ForumUserProfileActionKind.friends => l10n.profileFriends,
      ForumUserProfileActionKind.settings => l10n.profileSettings,
      ForumUserProfileActionKind.creditHistory => l10n.profileCreditHistory,
    };
  }

  IconData _iconFor(ForumUserProfileActionKind kind) => switch (kind) {
    ForumUserProfileActionKind.threads => Icons.article_outlined,
    ForumUserProfileActionKind.blogs => Icons.edit_note_outlined,
    ForumUserProfileActionKind.forumFavorites => Icons.bookmarks_outlined,
    ForumUserProfileActionKind.messages => Icons.notifications_outlined,
    ForumUserProfileActionKind.friends => Icons.people_outline,
    ForumUserProfileActionKind.settings => Icons.manage_accounts_outlined,
    ForumUserProfileActionKind.creditHistory =>
      Icons.account_balance_wallet_outlined,
  };
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
        key: Key('user-profile-action-${action.kind.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: action.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    maxLines: 2,
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

class _EmptyDetailsCard extends StatelessWidget {
  const _EmptyDetailsCard({required this.palette});

  final _UserProfilePalette palette;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('user-profile-empty-details'),
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration(palette),
    child: Text(
      AppLocalizations.of(context).profileNoAdditionalDetails,
      textAlign: TextAlign.center,
      style: TextStyle(color: palette.muted),
    ),
  );
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
    this.message,
    this.onOpenForumPage,
  });

  final Object? error;
  final String? message;
  final _UserProfilePalette palette;
  final VoidCallback onRetry;
  final VoidCallback? onOpenForumPage;

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
              message ?? _profileErrorText(context, error),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.body),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: onRetry,
                  child: Text(AppLocalizations.of(context).commonRetry),
                ),
                if (onOpenForumPage != null)
                  OutlinedButton(
                    key: const Key('my-profile-open-forum-page'),
                    onPressed: onOpenForumPage,
                    child: Text(
                      AppLocalizations.of(context).profileOpenForumPage,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAction {
  const _ProfileAction(this.kind, this.label, this.icon, {required this.onTap});

  final ForumUserProfileActionKind kind;
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
