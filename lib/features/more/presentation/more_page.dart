import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/main_navigation_settings_controller.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/auth/presentation/login_webview_page.dart';
import 'package:y300/features/comic/presentation/comic_download_queue_page.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_unused_image_management_page.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/more/presentation/about_page.dart';
import 'package:y300/features/more/presentation/appearance_settings_sheet.dart';
import 'package:y300/features/more/presentation/data_storage_sheet.dart';
import 'package:y300/features/more/presentation/more_debug_tools.dart';
import 'package:y300/features/more/presentation/more_account_action.dart';
import 'package:y300/features/more/presentation/more_account_header.dart';
import 'package:y300/features/more/presentation/navigation_management_page.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_sheet.dart';
import 'package:y300/features/profile/presentation/current_account_summary_controller.dart';
import 'package:y300/features/profile/presentation/current_account_avatar_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
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
  bool _openingLogin = false;
  bool _openingDailySignIn = false;
  bool _confirmingLogout = false;

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
    final authSession =
        ref.watch(authSessionControllerProvider).asData?.value ??
        const AuthSessionViewState.signedOut();
    final forumMode =
        ref.watch(forumShellModeControllerProvider).asData?.value ??
        ForumShellMode.defaultMode;
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
            isPending: _openingLogin || _confirmingLogout,
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
              isAccountActionPending: _openingLogin || _confirmingLogout,
            ),
            const Divider(
              key: Key('more-account-divider'),
              height: 1,
              indent: 0,
              endIndent: 0,
            ),
            ListTile(
              key: const Key('more-daily-sign-in-entry'),
              leading: const Icon(Icons.event_available_outlined),
              title: Text(l10n.moreDailySignIn),
              onTap: _openingDailySignIn
                  ? null
                  : () => _openDailySignInSheet(context),
            ),
            ListTile(
              key: const Key('more-unused-images-entry'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.moreUnusedImages),
              onTap: () => _openUnusedImagesPage(context, authSession),
            ),
            const Divider(
              key: Key('more-settings-divider'),
              height: 1,
              indent: 0,
              endIndent: 0,
            ),
            ListTile(
              key: const Key('more-forum-mode-entry'),
              leading: const Icon(Icons.public_outlined),
              title: Text(l10n.moreForumDisplayMode),
              onTap: () => _showForumModeSheet(context, ref, forumMode),
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

  // 内容含迁移状态卡与总览，可能超过默认半屏高度，允许抽屉撑满。
  Future<void> _showDataStorageSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const DataStorageSheet(),
    );
  }

  Future<void> _showForumModeSheet(
    BuildContext context,
    WidgetRef ref,
    ForumShellMode currentMode,
  ) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('more-forum-mode-option-webview'),
                leading: const Icon(Icons.language_outlined),
                title: Text(l10n.moreForumModeWebView),
                trailing: currentMode == ForumShellMode.webview
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => _setForumMode(
                  pageContext: context,
                  sheetContext: sheetContext,
                  ref: ref,
                  mode: ForumShellMode.webview,
                ),
              ),
              ListTile(
                key: const Key('more-forum-mode-option-native'),
                leading: const Icon(Icons.forum_outlined),
                title: Text(l10n.moreForumModeNative),
                trailing: currentMode == ForumShellMode.native
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => _setForumMode(
                  pageContext: context,
                  sheetContext: sheetContext,
                  ref: ref,
                  mode: ForumShellMode.native,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setForumMode({
    required BuildContext pageContext,
    required BuildContext sheetContext,
    required WidgetRef ref,
    required ForumShellMode mode,
  }) async {
    final l10n = AppLocalizations.of(pageContext);
    try {
      await ref.read(forumShellModeControllerProvider.notifier).setMode(mode);
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
    } catch (error) {
      if (!pageContext.mounted) {
        return;
      }
      ScaffoldMessenger.of(pageContext)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.moreForumModeSwitchFailed('$error'))),
        );
    }
  }

  Future<bool> _openLoginPage(BuildContext context) async {
    if (_openingLogin || _confirmingLogout) return false;
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

  Future<void> _openDailySignInSheet(BuildContext context) async {
    if (_openingDailySignIn || _openingLogin || _confirmingLogout) return;
    setState(() => _openingDailySignIn = true);
    try {
      if (ref.read(authSessionControllerProvider).asData?.value.isLoggedIn !=
          true) {
        await _openLoginPage(context);
        return;
      }
      final owner = ref.read(verifiedProfileOwnerProvider);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const DailySignInSheet(),
      );
      await _refreshAccountAfterVisit(owner);
    } finally {
      if (mounted) setState(() => _openingDailySignIn = false);
    }
  }

  Future<void> _refreshAccountAfterVisit(VerifiedProfileOwner? owner) async {
    // A different session already starts its own initial read. Do not refresh
    // that new account on behalf of the route opened by the previous owner.
    if (!mounted ||
        owner == null ||
        ref.read(verifiedProfileOwnerProvider) != owner) {
      return;
    }
    await ref.read(currentAccountSummaryControllerProvider.notifier).refresh();
  }

  Future<void> _openUnusedImagesPage(
    BuildContext context,
    AuthSessionViewState session,
  ) async {
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
    if (_openingMyProfile || _openingLogin || _confirmingLogout) return;
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
      final owner = ref.read(verifiedProfileOwnerProvider);
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
        initialSession == null ||
        !initialSession.isLoggedIn ||
        initialSession.isLoggingOut) {
      return;
    }
    final initialOwner = ref.read(verifiedProfileOwnerProvider);
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
          ref.read(verifiedProfileOwnerProvider) != initialOwner) {
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
