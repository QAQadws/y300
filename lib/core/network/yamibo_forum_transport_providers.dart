import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/waf/waf.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import 'package:y300/core/network/yamibo_forum_client_host_adapters.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';

final loggerProvider = Provider<Logger>((ref) {
  return Logger();
});

final cookieStoreProvider = Provider<CookieStore>((ref) {
  return CookieStore();
});

/// WebView → Dio Cookie 同步服务。
final webViewCookieSyncServiceProvider = Provider<WebViewCookieSyncService>((
  ref,
) {
  return WebViewCookieSyncService(
    cookieJar: InAppWebViewCookieJar(),
    cookieStore: ref.watch(cookieStoreProvider),
  );
});

/// 原生请求与应用根部后台 WAF WebView 之间的进程级协调器。
final wafChallengeRecoveryCoordinatorProvider =
    Provider<WafChallengeRecoveryCoordinator>((ref) {
      return WafChallengeRecoveryCoordinator();
    });

final yamiboSessionStoreProvider = Provider<YamiboSessionStore>((ref) {
  return YamiboSessionStore();
});

final yamiboHttpGatewayProvider = Provider<YamiboHttpGateway>((ref) {
  return YamiboHttpGateway(
    cookieStore: ref.watch(cookieStoreProvider),
    logger: ref.watch(loggerProvider),
    wafChallengeRecoveryCoordinator: ref.watch(
      wafChallengeRecoveryCoordinatorProvider,
    ),
  );
});

/// 后台 WAF WebView 挂载期间使用的原生通行验证探针。
final wafChallengeClearanceProbeProvider = Provider<WafChallengeClearanceProbe>(
  (ref) {
    final gateway = ref.watch(yamiboHttpGatewayProvider);
    return ({required uri, required userAgent}) =>
        gateway.probeWafChallengeClearance(uri, userAgent: userAgent);
  },
);

final wafChallengeVerificationServiceProvider =
    Provider<WafChallengeVerificationService>((ref) {
      return WafChallengeVerificationService(
        syncCookies: (uri) async {
          await ref.read(webViewCookieSyncServiceProvider).syncToStore(uri);
        },
        probe: ref.watch(wafChallengeClearanceProbeProvider),
      );
    });

final forumImageRefererProvider = Provider<String>((ref) {
  return '${AppConfig.siteBaseUrl}/';
});

final forumImageRefererForSourceProvider = Provider.family<String, String?>((
  ref,
  referer,
) {
  final normalized = referer?.trim();
  return normalized == null || normalized.isEmpty
      ? ref.watch(forumImageRefererProvider)
      : normalized;
});

final yamiboForumClientConfigProvider = Provider<ForumClientConfig>((ref) {
  return ForumClientConfig(
    siteOrigin: Uri.parse(AppConfig.siteBaseUrl),
    apiOrigin: Uri.parse(AppConfig.apiBaseUrl),
    userAgent: BrowserUserAgents.mobile,
    desktopUserAgent: BrowserUserAgents.desktop,
    apiUserAgent: BrowserUserAgents.mobile,
    resourceUserAgent: BrowserUserAgents.desktop,
    connectTimeout: AppConfig.connectTimeout,
    receiveTimeout: AppConfig.receiveTimeout,
  );
});

final yamiboForumClientNetworkProvider =
    Provider<Y300ForumClientNetworkAdapter>((ref) {
      return Y300ForumClientNetworkAdapter(
        gateway: ref.watch(yamiboHttpGatewayProvider),
        apiOrigin: Uri.parse(AppConfig.apiBaseUrl),
        siteOrigin: Uri.parse(AppConfig.siteBaseUrl),
        resourceUserAgent: BrowserUserAgents.desktop,
      );
    });

final yamiboForumResourceClientProvider = Provider<ForumResourceClient>((ref) {
  return ref.watch(yamiboForumClientNetworkProvider);
});

final yamiboForumResourceReferenceResolverProvider =
    Provider<ForumResourceReferenceResolver>((ref) {
      return ForumResourceReferenceResolver(
        siteOrigin: ref.watch(yamiboForumClientConfigProvider).siteOrigin,
      );
    });
