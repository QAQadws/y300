import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/main_navigation_settings_controller.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/auth/application/auth_session_controller.dart';
import 'package:y300/features/auth/presentation/login_webview_page.dart';
import 'package:y300/features/comic/presentation/comic_download_queue_page.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_unused_image_management_page.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/more/presentation/about_page.dart';
import 'package:y300/features/more/presentation/appearance_settings_sheet.dart';
import 'package:y300/features/more/presentation/data_storage_sheet.dart';
import 'package:y300/features/more/presentation/more_debug_tools.dart';
import 'package:y300/features/more/presentation/more_account_action.dart';
import 'package:y300/features/more/presentation/more_account_header.dart';
import 'package:y300/features/more/presentation/navigation_management_page.dart';
import 'package:y300/features/profile/presentation/current_account_summary_controller.dart';
import 'package:y300/features/profile/presentation/current_account_avatar_controller.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/profile/presentation/profile_action_navigation.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

class MorePage extends ConsumerStatefulWidget {
  const MorePage({super.key});

  @override
  ConsumerState<MorePage> createState() => _MorePageState();
}

class _MorePageState extends ConsumerState<MorePage> {
  final MoreDebugTools _debugTools = const MoreDebugTools();
  bool _openingMyProfile = false;
  bool _openingMyContent = false;
  bool _openingMyCredits = false;
  bool _openingLogin = false;
  bool _confirmingLogout = false;

  bool get _accountActionPending =>
      _openingLogin ||
      _confirmingLogout ||
      _openingMyProfile ||
      _openingMyContent ||
      _openingMyCredits;

  @override
  Widget build(BuildContext context) {
    ref.watch(
      currentAccountAvatarControllerProvider.select((state) => state.uid),
    );
    // Retain the summary while More is mounted, including when its header is
    // scrolled offscreen and the ListView disposes that child.
    ref.watch(
      currentAccountSummaryControllerProvider.select((state) => state.owner),
    );
    final auth = ref.watch(authSessionControllerProvider);
    final authSession =
        auth.asData?.value ?? const AuthSessionViewState.signedOut();
    final owner = ref.watch(verifiedSessionOwnerProvider);
    final canOpenMyContent =
        !_accountActionPending &&
        !auth.isLoading &&
        !auth.hasError &&
        !authSession.verificationInconclusive &&
        !authSession.isLoggingOut &&
        (!authSession.isLoggedIn || owner != null);
    final navigationState = ref
        .watch(mainNavigationSettingsControllerProvider)
        .value;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moreTitle),
        actions: [
          MoreAccountAction(
            onLogin: () => _openLoginPage(context),
            onLogout: () => _confirmAndLogout(context, ref),
            isPending: _accountActionPending,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(currentAccountSummaryControllerProvider.notifier)
            .refresh(),
        child: ListView(
          key: const Key('more-page-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            MoreAccountHeader(
              onOpenProfile: _openingMyProfile
                  ? null
                  : () => _openMyProfilePage(context),
              onOpenThreads: () =>
                  _openMyThreadsPage(UserThreadDirectoryType.threads),
              onOpenReplies: () =>
                  _openMyThreadsPage(UserThreadDirectoryType.replies),
              onOpenCredits: _openMyCreditsPage,
              isAccountActionPending: _accountActionPending,
            ),
            const Divider(
              key: Key('more-account-divider'),
              height: 1,
              indent: 0,
              endIndent: 0,
            ),
            ListTile(
              key: const Key('more-my-messages-entry'),
              leading: const Icon(Icons.mail_outline),
              title: Text(l10n.moreMyMessages),
              onTap: canOpenMyContent
                  ? () =>
                        _openMyContentPage(ForumUserProfileActionKind.messages)
                  : null,
            ),
            ListTile(
              key: const Key('more-my-blogs-entry'),
              leading: const Icon(Icons.auto_stories_outlined),
              title: Text(l10n.profileMyBlogs),
              onTap: canOpenMyContent
                  ? () => _openMyContentPage(ForumUserProfileActionKind.blogs)
                  : null,
            ),
            ListTile(
              key: const Key('more-my-friends-entry'),
              leading: const Icon(Icons.people_outline_rounded),
              title: Text(l10n.profileMyFriendsTitle),
              onTap: canOpenMyContent
                  ? () => _openMyContentPage(ForumUserProfileActionKind.friends)
                  : null,
            ),
            ListTile(
              key: const Key('more-unused-images-entry'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.moreUnusedImages),
              onTap: _accountActionPending
                  ? null
                  : () => _openUnusedImagesPage(context, authSession),
            ),
            const Divider(
              key: Key('more-settings-divider'),
              height: 1,
              indent: 0,
              endIndent: 0,
            ),
            ListTile(
              key: const Key('more-appearance-entry'),
              leading: const Icon(Icons.palette_outlined),
              title: Text(l10n.moreAppearance),
              onTap: () => _showAppearanceSettingsSheet(context),
            ),
            ListTile(
              key: const Key('more-navigation-management-entry'),
              leading: const Icon(Icons.view_week_outlined),
              title: Text(l10n.moreNavigationManagement),
              onTap: navigationState == null
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const NavigationManagementPage(),
                        ),
                      );
                    },
            ),
            ListTile(
              key: const Key('more-data-storage-entry'),
              leading: const Icon(Icons.storage_outlined),
              title: Text(l10n.moreDataAndStorage),
              onTap: () => _showDataStorageSheet(context),
            ),
            ListTile(
              key: const Key('more-download-queue-entry'),
              leading: const Icon(Icons.offline_pin_outlined),
              title: Text(l10n.moreDownloadQueue),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ComicDownloadQueuePage(),
                  ),
                );
              },
            ),
            ..._debugTools.buildTiles(context, l10n),
            ListTile(
              key: const Key('more-about-entry'),
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.moreAbout),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAppearanceSettingsSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) => const AppearanceSettingsSheet(),
    );
  }

  Future<void> _openMyThreadsPage(UserThreadDirectoryType type) =>
      _openMyContentPage(
        type == UserThreadDirectoryType.replies
            ? ForumUserProfileActionKind.replies
            : ForumUserProfileActionKind.threads,
      );

  Future<void> _openMyContentPage(ForumUserProfileActionKind action) async {
    if (!mounted ||
        _accountActionPending ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    var session = ref.read(authSessionControllerProvider).asData?.value;
    if (session == null || session.isLoggingOut) return;
    if (!session.isLoggedIn) {
      // The login flow holds its own pending state until this visit resumes.
      final loggedIn = await _openLoginPage(context);
      if (!mounted || !loggedIn) return;
      session = ref.read(authSessionControllerProvider).asData?.value;
    }
    if (session == null ||
        !session.isLoggedIn ||
        session.isLoggingOut ||
        _accountActionPending ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final owner = ref.read(verifiedSessionOwnerProvider);
    if (owner == null) return;
    setState(() => _openingMyContent = true);
    try {
      await openProfileNativeAction(
        context: context,
        ref: ref,
        action: action,
        userId: owner.uid,
        isMyProfile: true,
        isCurrentOwner: () =>
            mounted && ref.read(verifiedSessionOwnerProvider) == owner,
      );
      await _refreshAccountAfterVisit(owner);
    } finally {
      if (mounted) setState(() => _openingMyContent = false);
    }
  }

  Future<void> _openMyCreditsPage() async {
    if (!mounted ||
        _accountActionPending ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final owner = ref.read(verifiedSessionOwnerProvider);
    if (owner == null) return;
    setState(() => _openingMyCredits = true);
    try {
      await Navigator.of(context).push<Object?>(
        ref.read(forumWebViewRouteFactoryProvider)(
          ForumWebViewLaunchConfig(
            initialUri: Uri.parse(AppConfig.siteBaseUrl).replace(
              path: '/plugin.php',
              queryParameters: {'id': 'zqlj_sign', 'mobile': '2'},
            ),
            popOnRootBack: true,
            purpose: ForumWebViewHostPurpose.form,
            navigationPolicy: ForumWebViewNavigationPolicy.keepWebView,
            expectedAccountId: owner.uid,
          ),
        ),
      );
      await _refreshAccountAfterVisit(owner);
    } finally {
      if (mounted) setState(() => _openingMyCredits = false);
    }
  }

  // 内容含迁移状态卡与总览，可能超过默认半屏高度，允许抽屉撑满。
  Future<void> _showDataStorageSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const DataStorageSheet(),
    );
  }

  Future<bool> _openLoginPage(BuildContext context) async {
    if (_openingLogin ||
        _confirmingLogout ||
        _openingMyContent ||
        _openingMyCredits) {
      return false;
    }
    setState(() => _openingLogin = true);
    try {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          settings: const RouteSettings(name: LoginWebViewPage.routeName),
          builder: (_) => const LoginWebViewPage(),
        ),
      );
      return result == true;
    } finally {
      if (mounted) setState(() => _openingLogin = false);
    }
  }

  Future<void> _refreshAccountAfterVisit(VerifiedSessionOwner? owner) async {
    // A different session already starts its own initial read. Do not refresh
    // that new account on behalf of the route opened by the previous owner.
    if (!mounted ||
        owner == null ||
        ref.read(verifiedSessionOwnerProvider) != owner) {
      return;
    }
    await ref.read(currentAccountSummaryControllerProvider.notifier).refresh();
  }

  Future<void> _openUnusedImagesPage(
    BuildContext context,
    AuthSessionViewState session,
  ) async {
    if (!mounted ||
        _accountActionPending ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    if (!session.isLoggedIn) {
      final loggedIn = await _openLoginPage(context);
      if (!loggedIn || !context.mounted) {
        return;
      }
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: ComposerUnusedImageManagementPage.routeName,
        ),
        builder: (_) => const ComposerUnusedImageManagementPage(),
      ),
    );
  }

  Future<void> _openMyProfilePage(BuildContext context) async {
    if (_openingMyProfile ||
        _openingMyContent ||
        _openingMyCredits ||
        _openingLogin ||
        _confirmingLogout) {
      return;
    }
    setState(() => _openingMyProfile = true);
    try {
      var session = ref.read(authSessionControllerProvider).asData?.value;
      if (session?.isLoggedIn != true) {
        final loggedIn = await _openLoginPage(context);
        if (!loggedIn || !context.mounted) return;
        // The login route returns true only after accepting its verified
        // session. Recheck state so a concurrent logout cannot continue here.
        session = ref.read(authSessionControllerProvider).asData?.value;
        if (session?.isLoggedIn != true) return;
      }
      if (!context.mounted) return;
      final owner = ref.read(verifiedSessionOwnerProvider);
      if (owner == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const MyProfilePage()),
      );
      await _refreshAccountAfterVisit(owner);
    } finally {
      if (mounted) setState(() => _openingMyProfile = false);
    }
  }

  Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
    final initialSession = ref
        .read(authSessionControllerProvider)
        .asData
        ?.value;
    if (_confirmingLogout ||
        _openingLogin ||
        _openingMyProfile ||
        _openingMyContent ||
        _openingMyCredits ||
        initialSession == null ||
        !initialSession.isLoggedIn ||
        initialSession.isLoggingOut) {
      return;
    }
    final initialOwner = ref.read(verifiedSessionOwnerProvider);
    setState(() => _confirmingLogout = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context).moreLogoutConfirmTitle),
          content: Text(AppLocalizations.of(context).moreLogoutConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton(
              key: const Key('more-logout-confirm-button'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(AppLocalizations.of(context).moreLogout),
            ),
          ],
        ),
      );
      if (!context.mounted ||
          confirmed != true ||
          ref.read(authSessionControllerProvider).asData?.value.uid !=
              initialSession.uid ||
          ref.read(verifiedSessionOwnerProvider) != initialOwner) {
        return;
      }

      final success = await ref
          .read(authSessionControllerProvider.notifier)
          .logout();
      if (!context.mounted) {
        return;
      }

      if (success) {
        ref.invalidate(forumHomeControllerProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).moreLogoutSuccess),
          ),
        );
        return;
      }

      final l10n = AppLocalizations.of(context);
      final failure = ref
          .read(authSessionControllerProvider)
          .asData
          ?.value
          .logoutFailure;
      final message = l10n.moreLogoutFailed(
        LocalizedErrorSummary.resolve(l10n, failure),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _confirmingLogout = false);
    }
  }
}
