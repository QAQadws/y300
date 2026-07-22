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
import 'package:y300/features/app_update/presentation/widgets/app_update_check_tile.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/presentation/comic_download_queue_page.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/more/presentation/appearance_settings_sheet.dart';
import 'package:y300/features/more/presentation/data_storage_page.dart';
import 'package:y300/features/more/presentation/more_debug_tools.dart';
import 'package:y300/features/more/presentation/navigation_management_page.dart';

class MorePage extends ConsumerStatefulWidget {
  const MorePage({super.key});

  @override
  ConsumerState<MorePage> createState() => _MorePageState();
}

class _MorePageState extends ConsumerState<MorePage> {
  final MoreDebugTools _debugTools = MoreDebugTools();

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
    final navigationState = ref
        .watch(mainNavigationSettingsControllerProvider)
        .value;
    final visibleNavigationCount =
        navigationState?.settings.visibleManagedDestinations.length ?? 5;

    return Scaffold(
      appBar: AppBar(title: const Text('更多')),
      body: ListView(
        children: [
          _AuthSessionTile(
            session: authSession,
            onLogin: () => _openLoginPage(context),
            onLogout: () => _confirmAndLogout(context, ref),
          ),
          ListTile(
            key: const Key('more-my-profile-entry'),
            leading: const Icon(Icons.person_outline),
            title: const Text('我的资料'),
            subtitle: Text(
              authSession.isLoggedIn
                  ? _myProfileSubtitle(authSession)
                  : '登录后查看个人资料、消息提醒',
            ),
            onTap: authSession.isLoggedIn
                ? () => _openMyProfileWebViewPage(context, authSession)
                : () => _openLoginPage(context),
          ),
          ListTile(
            key: const Key('more-forum-mode-entry'),
            leading: const Icon(Icons.public_outlined),
            title: const Text('论坛显示模式'),
            subtitle: Text('当前：${forumMode.displayLabel}'),
            onTap: () => _showForumModeSheet(context, ref, forumMode),
          ),
          ListTile(
            key: const Key('more-appearance-entry'),
            leading: const Icon(Icons.palette_outlined),
            title: const Text('外观与文字'),
            subtitle: Text(
              '当前：${appearanceSettings.themePreference.displayLabel}',
            ),
            onTap: () => _showAppearanceSettingsSheet(context),
          ),
          ListTile(
            key: const Key('more-navigation-management-entry'),
            leading: const Icon(Icons.view_week_outlined),
            title: const Text('导航栏管理'),
            subtitle: Text('已显示 $visibleNavigationCount 项'),
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
            title: const Text('数据与存储'),
            subtitle: const Text('管理图片缓存与下载位置'),
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
                title: const Text('下载队列'),
                subtitle: Text(_downloadQueueSummary(snapshot)),
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
          ..._debugTools.buildTiles(context, ref),
          const AppUpdateCheckTile(),
          ListTile(
            key: const Key('more-about-placeholder'),
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: Text(_debugTools.aboutSubtitle(ref)),
            onTap: () => _debugTools.handleAboutTap(context, ref),
          ),
        ],
      ),
    );
  }

  String _downloadQueueSummary(ComicDownloadQueueSnapshot snapshot) {
    final active = snapshot.activeEntry;
    if (active != null) {
      final total = active.totalImages;
      final progress = total == null || total <= 0
          ? '正在解析图片'
          : '${active.completedImages}/$total';
      final waiting = snapshot.waitingCount;
      return '正在下载《${active.comicTitle}》 ${active.episodeTitle} · '
          '$progress${waiting > 0 ? ' · 等待 $waiting' : ''}';
    }
    if (snapshot.waitingCount > 0) {
      return '等待下载 · ${snapshot.waitingCount} 个任务';
    }
    if (snapshot.failedCount > 0) {
      return '${snapshot.failedCount} 个任务下载失败';
    }
    return '暂无下载任务';
  }

  Future<void> _showAppearanceSettingsSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const AppearanceSettingsSheet(),
    );
  }

  Future<void> _showForumModeSheet(
    BuildContext context,
    WidgetRef ref,
    ForumShellMode currentMode,
  ) {
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
                title: const Text('WebView 模式'),
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
                title: const Text('解析模式'),
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
        ..showSnackBar(SnackBar(content: Text('论坛显示模式切换失败：$error')));
    }
  }

  Future<void> _openLoginPage(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: LoginWebViewPage.routeName),
        builder: (_) => const LoginWebViewPage(),
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

  String _myProfileSubtitle(AuthSessionViewState session) {
    final username = session.username.trim();
    if (username.isEmpty) {
      return '查看个人资料、消息提醒';
    }
    return '$username 的资料与消息提醒';
  }

  Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后会清除本地论坛登录状态。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('more-logout-confirm-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已退出登录')));
      return;
    }

    final message =
        ref.read(authSessionControllerProvider).asData?.value.errorMessage ??
        '退出登录失败';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AuthSessionTile extends StatelessWidget {
  const _AuthSessionTile({
    required this.session,
    required this.onLogin,
    required this.onLogout,
  });

  final AuthSessionViewState session;
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
        title: const Text('退出登录'),
        subtitle: Text(_logoutSubtitle),
        enabled: !session.isLoggingOut,
        onTap: session.isLoggingOut ? null : onLogout,
      );
    }

    return ListTile(
      key: const Key('more-login-entry'),
      leading: const Icon(Icons.login),
      title: const Text('登录'),
      subtitle: const Text('登录论坛账号并同步登录状态'),
      onTap: onLogin,
    );
  }

  String get _logoutSubtitle {
    final username = session.username.trim();
    if (username.isEmpty) {
      return '退出当前论坛账号';
    }
    return '当前账号：$username';
  }
}
