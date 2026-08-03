import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/main_navigation_settings_controller.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/auth/presentation/login_webview_page.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/presentation/comic_download_queue_page.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_unused_image_management_page.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/more/data/about_providers.dart';
import 'package:y300/features/more/presentation/about_page.dart';
import 'package:y300/features/more/presentation/appearance_settings_sheet.dart';
import 'package:y300/features/more/presentation/data_storage_page.dart';
import 'package:y300/features/more/presentation/more_debug_tools.dart';
import 'package:y300/features/more/presentation/more_text_resolver.dart';
import 'package:y300/features/more/presentation/navigation_management_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

class MorePage extends ConsumerStatefulWidget {
  const MorePage({super.key});

  @override
  ConsumerState<MorePage> createState() => _MorePageState();
}

class _MorePageState extends ConsumerState<MorePage> {
  final MoreDebugTools _debugTools = const MoreDebugTools();

  @override
  Widget build(BuildContext context) {
    final authSession =
        ref.watch(authSessionControllerProvider).asData?.value ??
        const AuthSessionViewState.signedOut();
    final forumMode =
        ref.watch(forumShellModeControllerProvider).asData?.value ??
        ForumShellMode.defaultMode;
    final appearanceSettings =
        ref.watch(appAppearanceControllerProvider).asData?.value ??
        AppAppearanceSettings.defaults();
    final downloadQueueSnapshot = ref.watch(comicDownloadQueueSnapshotProvider);
    final appInfo = ref.watch(aboutAppInfoProvider).value;
    final navigationState = ref
        .watch(mainNavigationSettingsControllerProvider)
        .value;
    final l10n = AppLocalizations.of(context);
    final visibleNavigationCount =
        navigationState?.settings.visibleManagedDestinations.length ?? 5;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.moreTitle)),
      body: ListView(
        children: [
          _AuthSessionTile(
            session: authSession,
            l10n: l10n,
            onLogin: () => _openLoginPage(context),
            onLogout: () => _confirmAndLogout(context, ref),
          ),
          ListTile(
            key: const Key('more-my-profile-entry'),
            leading: const Icon(Icons.person_outline),
            title: Text(l10n.moreMyProfile),
            subtitle: Text(
              authSession.isLoggedIn
                  ? _myProfileSubtitle(l10n, authSession)
                  : l10n.moreMyProfileSignedOutSubtitle,
            ),
            onTap: authSession.isLoggedIn
                ? () => _openMyProfileWebViewPage(context, authSession)
                : () => _openLoginPage(context),
          ),
          ListTile(
            key: const Key('more-unused-images-entry'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.moreUnusedImages),
            subtitle: Text(l10n.moreUnusedImagesSubtitle),
            onTap: () => _openUnusedImagesPage(context, authSession),
          ),
          ListTile(
            key: const Key('more-forum-mode-entry'),
            leading: const Icon(Icons.public_outlined),
            title: Text(l10n.moreForumDisplayMode),
            subtitle: Text(
              l10n.moreForumCurrentMode(
                MoreTextResolver.forumModeLabel(l10n, forumMode),
              ),
            ),
            onTap: () => _showForumModeSheet(context, ref, forumMode),
          ),
          ListTile(
            key: const Key('more-appearance-entry'),
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n.moreAppearance),
            subtitle: Text(
              l10n.moreCurrentTheme(
                MoreTextResolver.themeLabel(
                  l10n,
                  appearanceSettings.themePreference,
                ),
              ),
            ),
            onTap: () => _showAppearanceSettingsSheet(context),
          ),
          ListTile(
            key: const Key('more-navigation-management-entry'),
            leading: const Icon(Icons.view_week_outlined),
            title: Text(l10n.moreNavigationManagement),
            subtitle: Text(
              l10n.moreVisibleNavigationCount(visibleNavigationCount),
            ),
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
            subtitle: Text(l10n.moreDataAndStorageSubtitle),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DataStoragePage(),
                ),
              );
            },
          ),
          ValueListenableBuilder<ComicDownloadQueueSnapshot>(
            valueListenable: downloadQueueSnapshot,
            builder: (context, snapshot, _) {
              return ListTile(
                key: const Key('more-download-queue-entry'),
                leading: const Icon(Icons.downloading_outlined),
                title: Text(l10n.moreDownloadQueue),
                subtitle: Text(_downloadQueueSummary(l10n, snapshot)),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ComicDownloadQueuePage(),
                    ),
                  );
                },
              );
            },
          ),
          ..._debugTools.buildTiles(context, l10n),
          ListTile(
            key: const Key('more-about-entry'),
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.moreAbout),
            subtitle: Text(
              appInfo == null
                  ? l10n.moreAboutSubtitle
                  : MoreTextResolver.aboutVersion(l10n, appInfo),
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AboutPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  String _downloadQueueSummary(
    AppLocalizations l10n,
    ComicDownloadQueueSnapshot snapshot,
  ) {
    final active = snapshot.activeEntry;
    if (active != null) {
      final total = active.totalImages;
      final progress = total == null || total <= 0
          ? l10n.moreDownloadParsingImages
          : '${active.completedImages}/$total';
      final waiting = snapshot.waitingCount;
      return l10n.moreDownloadActiveProgress(
        active.comicTitle,
        active.episodeTitle,
        progress,
        waiting,
      );
    }
    if (snapshot.waitingCount > 0) {
      return l10n.moreDownloadWaiting(snapshot.waitingCount);
    }
    if (snapshot.failedCount > 0) {
      return l10n.moreDownloadFailed(snapshot.failedCount);
    }
    return l10n.moreDownloadEmpty;
  }

  Future<void> _showAppearanceSettingsSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) => const AppearanceSettingsSheet(),
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
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: LoginWebViewPage.routeName),
        builder: (_) => const LoginWebViewPage(),
      ),
    );
    return result == true;
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

  void _openMyProfileWebViewPage(
    BuildContext context,
    AuthSessionViewState session,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
          overrides: [
            forumWebViewInitialUriProvider.overrideWithValue(
              _buildMyProfileUri(session),
            ),
            forumWebViewPopOnRootBackProvider.overrideWithValue(true),
            forumWebViewDriverProvider.overrideWith((ref) {
              final factory = ref.watch(forumWebViewDriverFactoryProvider);
              return factory();
            }),
            forumWebViewControllerProvider.overrideWith(
              ForumWebViewController.new,
            ),
          ],
          child: const ForumWebViewPage(),
        ),
      ),
    );
  }

  Uri _buildMyProfileUri(AuthSessionViewState session) {
    return Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'uid': session.uid,
        'do': 'profile',
        'mycenter': '1',
        'mobile': '2',
      },
    );
  }

  String _myProfileSubtitle(
    AppLocalizations l10n,
    AuthSessionViewState session,
  ) {
    final username = session.username.trim();
    if (username.isEmpty) {
      return l10n.moreMyProfileSignedOutSubtitle;
    }
    return l10n.moreMyProfileSubtitle(username);
  }

  Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
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
    if (confirmed != true) {
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
        SnackBar(content: Text(AppLocalizations.of(context).moreLogoutSuccess)),
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
  }
}

class _AuthSessionTile extends StatelessWidget {
  const _AuthSessionTile({
    required this.session,
    required this.l10n,
    required this.onLogin,
    required this.onLogout,
  });

  final AuthSessionViewState session;
  final AppLocalizations l10n;
  final VoidCallback onLogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    if (session.isLoggedIn) {
      return ListTile(
        key: const Key('more-logout-entry'),
        leading: session.isLoggingOut
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.logout),
        title: Text(l10n.moreLogout),
        subtitle: Text(_logoutSubtitle),
        enabled: !session.isLoggingOut,
        onTap: session.isLoggingOut ? null : onLogout,
      );
    }

    return ListTile(
      key: const Key('more-login-entry'),
      leading: const Icon(Icons.login),
      title: Text(l10n.moreLogin),
      subtitle: Text(l10n.moreLoginSubtitle),
      onTap: onLogin,
    );
  }

  String get _logoutSubtitle {
    final username = session.username.trim();
    if (username.isEmpty) {
      return l10n.moreLogoutSubtitle;
    }
    return l10n.moreLogoutSubtitleUsername(username);
  }
}
