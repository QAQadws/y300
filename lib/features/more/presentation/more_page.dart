import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/library_shared/presentation/controllers/sync_diagnostic_mode_controller.dart';
import 'package:y300/features/auth/presentation/login_webview_page.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/more/presentation/appearance_settings_page.dart';
import 'package:y300/features/more/presentation/data_storage_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_diagnostic_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_html_first_render_mode_controller.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_page.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_renderer_prototype_page.dart';

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
    final threadDiagnosticEnabled =
        ref.watch(threadDetailDiagnosticControllerProvider).asData?.value ??
        false;
    final htmlFirstRenderMode = ref
        .watch(threadDetailHtmlFirstRenderModeControllerProvider)
        .asData
        ?.value;
    final htmlFirstRendererEnabled = htmlFirstRenderMode?.isHtmlFirst ?? false;

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
          if (kDebugMode) ...[
            ListTile(
              key: const Key('more-composer-quill-prototype-entry'),
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('Quill Composer 原型'),
              subtitle: const Text('验证所见即所得到 Discuz BBCode 的转换'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ComposerQuillPrototypePage(),
                  ),
                );
              },
            ),
            ListTile(
              key: const Key('more-html-renderer-prototype-entry'),
              leading: const Icon(Icons.article_outlined),
              title: const Text('HTML 正文渲染原型'),
              subtitle: const Text('验证复杂正文 HTML 的原生渲染'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ForumHtmlRendererPrototypePage(),
                  ),
                );
              },
            ),
          ],
          if (diagnosticEnabled) ...[
            SwitchListTile(
              key: const Key('more-thread-detail-diagnostic-switch'),
              secondary: const Icon(Icons.bug_report_outlined),
              title: const Text('帖子详情滚动诊断'),
              subtitle: const Text('记录 entry 构建、render plan 和滚动操作'),
              value: threadDiagnosticEnabled,
              onChanged: (value) =>
                  _setThreadDetailDiagnosticEnabled(context, ref, value),
            ),
            SwitchListTile(
              key: const Key('thread-detail-html-first-renderer-switch'),
              secondary: const Icon(Icons.article_outlined),
              title: const Text('HTML-first 对照入口'),
              subtitle: const Text('正文已默认使用 HTML-first；此开关仅显示旧渲染对照入口'),
              value: htmlFirstRendererEnabled,
              onChanged: (value) =>
                  _setThreadDetailHtmlFirstRendererEnabled(context, ref, value),
            ),
            ListTile(
              key: const Key('more-thread-detail-diagnostic-copy-entry'),
              leading: const Icon(Icons.content_copy_outlined),
              title: const Text('复制帖子详情诊断日志'),
              subtitle: const Text('复制当前进程内最近的滚动诊断事件'),
              onTap: () => _copyThreadDetailDiagnosticLog(context, ref),
            ),
          ],
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

  Future<void> _setThreadDetailDiagnosticEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    try {
      await ref
          .read(threadDetailDiagnosticControllerProvider.notifier)
          .setEnabled(enabled);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('帖子详情诊断设置失败：$error')));
    }
  }

  Future<void> _copyThreadDetailDiagnosticLog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final text = ref
        .read(threadDetailDiagnosticControllerProvider.notifier)
        .exportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text.trim().isEmpty ? '暂无帖子详情诊断日志' : '帖子详情诊断日志已复制'),
      ),
    );
  }

  Future<void> _setThreadDetailHtmlFirstRendererEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    try {
      await ref
          .read(threadDetailHtmlFirstRenderModeControllerProvider.notifier)
          .setHtmlFirstEnabled(enabled);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('HTML-first 对照设置失败：$error')));
    }
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
