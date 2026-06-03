import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/more/presentation/data_storage_page.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authSession = ref.watch(authSessionControllerProvider).asData?.value ??
        const AuthSessionViewState.signedOut();
    final forumMode = ref.watch(forumShellModeControllerProvider).asData?.value ??
        ForumShellMode.webview;

    return Scaffold(
      appBar: AppBar(title: const Text('更多')),
      body: ListView(
        children: [
          _AuthSessionTile(
            session: authSession,
            onLogin: () => _openLoginPage(context, ref),
            onLogout: () => _confirmAndLogout(context, ref),
          ),
          ListTile(
            key: const Key('more-forum-mode-entry'),
            leading: const Icon(Icons.public_outlined),
            title: const Text('论坛显示模式'),
            subtitle: Text('当前：${forumMode.displayLabel}'),
            onTap: () => _showForumModeSheet(context, ref, forumMode),
          ),
          ListTile(
            key: const Key('more-data-storage-entry'),
            leading: const Icon(Icons.storage_outlined),
            title: const Text('数据与存储'),
            subtitle: const Text('管理图片缓存与下载位置'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DataStoragePage()),
              );
            },
          ),
          const ListTile(
            key: Key('more-reader-settings-placeholder'),
            leading: Icon(Icons.menu_book_outlined),
            title: Text('阅读设置（预留）'),
            subtitle: Text('后续阶段接入阅读器细项配置'),
          ),
          const ListTile(
            key: Key('more-about-placeholder'),
            leading: Icon(Icons.info_outline),
            title: Text('关于（预留）'),
            subtitle: Text('后续阶段补充版本与帮助信息'),
          ),
        ],
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
        ..showSnackBar(
          SnackBar(content: Text('论坛显示模式切换失败：$error')),
        );
    }
  }

  Future<void> _openLoginPage(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
    );
    if (result == true) {
      ref.invalidate(authSessionControllerProvider);
      ref.invalidate(forumHomeControllerProvider);
    }
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

    final success = await ref.read(authSessionControllerProvider.notifier).logout();
    if (!context.mounted) {
      return;
    }

    if (success) {
      ref.invalidate(forumHomeControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已退出登录')),
      );
      return;
    }

    final message = ref.read(authSessionControllerProvider).asData?.value.errorMessage ??
        '退出登录失败';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
