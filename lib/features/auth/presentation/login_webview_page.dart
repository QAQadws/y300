import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/features/auth/data/services/webview_login_progress.dart';
import 'package:y300/features/auth/data/services/webview_login_session_resolver.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';

/// 基于 WebView 的登录页。
///
/// 直接加载 Discuz 移动端登录页，让真实浏览器环境解开阿里云 WAF 挑战并完成
/// 登录；每次页面加载完成后通过 [WebViewLoginSessionResolver] 把 cookie 回灌
/// dio 并判定登录态。登录成功后填充全局会话并返回 true。
///
/// 刻意不复用重型的论坛 WebView 壳（ForumWebViewPage）——登录是一次性、职责
/// 单一的流程，独立轻量页面能保持模块边界清晰。
class LoginWebViewPage extends ConsumerStatefulWidget {
  const LoginWebViewPage({super.key});

  /// 路由名，供导航埋点与测试断言识别登录页入栈。
  static const String routeName = 'login-webview';

  static final Uri loginUri = Uri.parse(
    'https://bbs.yamibo.com/member.php?mod=logging&action=login&mobile=2',
  );

  @override
  ConsumerState<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends ConsumerState<LoginWebViewPage> {
  int _loadProgress = 0;
  bool _isVerifying = false;
  bool _didComplete = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        bottom: _loadProgress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _loadProgress / 100),
              )
            : null,
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          Expanded(
            child: inapp.InAppWebView(
              initialUrlRequest: inapp.URLRequest(
                url: inapp.WebUri(LoginWebViewPage.loginUri.toString()),
              ),
              initialSettings: inapp.InAppWebViewSettings(
                javaScriptEnabled: true,
                userAgent: BrowserUserAgents.mobile,
                transparentBackground: true,
              ),
              onProgressChanged: (controller, progress) {
                if (!mounted) {
                  return;
                }
                setState(() => _loadProgress = progress);
              },
              onLoadStop: (controller, url) => _handlePageFinished(),
            ),
          ),
        ],
      ),
    );
  }

  /// 页面加载完成回调：同步 cookie 并判定登录态。加了并发/一次性守卫，避免
  /// 登录成功后仍在途的页面加载重复触发校验或重复 pop。
  Future<void> _handlePageFinished() async {
    if (_didComplete || _isVerifying) {
      return;
    }
    _isVerifying = true;
    try {
      final resolver = ref.read(webViewLoginSessionResolverProvider);
      final progress = await resolver.evaluate();
      if (!mounted) {
        return;
      }
      switch (progress) {
        case WebViewLoginSucceeded(:final session):
          _didComplete = true;
          ref
              .read(authSessionControllerProvider.notifier)
              .acceptSession(session);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('登录成功')));
          Navigator.of(context).pop(true);
        case WebViewLoginFailed(:final message):
          setState(() => _errorMessage = '登录校验失败：$message');
        case WebViewLoginPending():
          // 用户还没提交或还在登录页，静默等待下一次页面加载。
          break;
      }
    } finally {
      _isVerifying = false;
    }
  }
}
