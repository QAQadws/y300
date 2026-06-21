import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/library_shared/presentation/controllers/sync_diagnostic_mode_controller.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/more/presentation/appearance_settings_page.dart';
import 'package:y300/features/more/presentation/data_storage_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';

class MorePage extends ConsumerStatefulWidget {
  const MorePage({super.key});

  @override
  ConsumerState<MorePage> createState() => _MorePageState();
}

class _MorePageState extends ConsumerState<MorePage> {
  static const int _diagnosticTapThreshold = 5;
  static const Duration _diagnosticTapWindow = Duration(seconds: 2);

  final List<DateTime> _aboutTapTimes = <DateTime>[];

  @override
  Widget build(BuildContext context) {
    final authSession =
        ref.watch(authSessionControllerProvider).asData?.value ??
        const AuthSessionViewState.signedOut();
    final forumMode =
        ref.watch(forumShellModeControllerProvider).asData?.value ??
        ForumShellMode.webview;
    final appearanceSettings =
        ref.watch(appAppearanceControllerProvider).asData?.value ??
        AppAppearanceSettings.defaults();
    final diagnosticMode = ref.watch(syncDiagnosticModeControllerProvider);
    final diagnosticEnabled = diagnosticMode.asData?.value ?? false;

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
                ? () => _openMyProfilePage(context)
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
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AppearanceSettingsPage(),
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
          const ListTile(
            key: Key('more-reader-settings-placeholder'),
            leading: Icon(Icons.menu_book_outlined),
            title: Text('阅读设置（预留）'),
            subtitle: Text('后续阶段接入阅读器细项配置'),
          ),
          ListTile(
            key: const Key('more-about-placeholder'),
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: Text(
              diagnosticEnabled
                  ? '已开启诊断日志模式，连续快速点击 5 次可关闭'
                  : '连续快速点击 5 次可开启诊断日志模式',
            ),
            onTap: _handleAboutTap,
          ),
        ],
      ),
    );
  }

  Future<void> _handleAboutTap() async {
    final now = DateTime.now();
    _aboutTapTimes.add(now);
    _aboutTapTimes.removeWhere(
      (time) => now.difference(time) > _diagnosticTapWindow,
    );
    if (_aboutTapTimes.length < _diagnosticTapThreshold) {
      return;
    }
    _aboutTapTimes.clear();
    final enabled = await ref
        .read(syncDiagnosticModeControllerProvider.notifier)
        .toggle();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            enabled ? '诊断日志模式已开启，后续会写入本地 diagnostics 日志' : '诊断日志模式已关闭',
          ),
        ),
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
                title: const Text('原生模式'),
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
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const LoginPage()));
  }

  void _openMyProfilePage(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MyProfilePage()));
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
