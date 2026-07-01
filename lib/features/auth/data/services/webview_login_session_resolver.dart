import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import 'package:y300/core/network/yamibo/yamibo_auth_cookie.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/auth/data/services/webview_login_progress.dart';

/// 编排 WebView 登录的“检测 + 校验”逻辑，与登录页 UI 解耦。
///
/// 每当登录 WebView 加载完成一个页面，页面调用 [evaluate]：
/// 1. 把 WebView cookie 回灌 dio（拿到 WAF 通行证 + 登录态 cookie）；
/// 2. 若尚未出现 `*_auth` 登录 cookie，返回 [WebViewLoginPending]；
/// 3. 出现后，用现有 [AuthRepository.refreshSession] 走 profile API 校验会话，
///    成功即 [WebViewLoginSucceeded]（此时 formhash 已写入会话存储，收藏等
///    API 功能随即可用），失败则 [WebViewLoginFailed]。
///
/// 这样登录成功检测基于“auth cookie 是否存在”这一可靠信号，而非猜测 URL 跳转。
class WebViewLoginSessionResolver {
  WebViewLoginSessionResolver({
    required WebViewCookieSyncService cookieSyncService,
    required AuthRepository authRepository,
  }) : _cookieSyncService = cookieSyncService,
       _authRepository = authRepository;

  final WebViewCookieSyncService _cookieSyncService;
  final AuthRepository _authRepository;

  static final Uri _siteUri = Uri.parse(AppConfig.siteBaseUrl);

  Future<WebViewLoginProgress> evaluate() async {
    final cookies = await _cookieSyncService.syncToStore(_siteUri);
    if (!YamiboAuthCookie.isLoggedIn(cookies)) {
      return const WebViewLoginPending();
    }

    // auth cookie 已就位且已回灌 dio，profile 校验此刻应能成功并顺带缓存 formhash。
    final result = await _authRepository.refreshSession();
    return result.when(
      success: (session) => session.isLoggedIn
          ? WebViewLoginSucceeded(session)
          : const WebViewLoginPending(),
      failure: (ApiError error) => WebViewLoginFailed(error.message),
    );
  }
}

final webViewLoginSessionResolverProvider =
    Provider<WebViewLoginSessionResolver>((ref) {
      return WebViewLoginSessionResolver(
        cookieSyncService: ref.watch(webViewCookieSyncServiceProvider),
        authRepository: ref.watch(authRepositoryProvider),
      );
    });
