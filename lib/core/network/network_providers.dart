import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/waf/waf.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import 'package:y300/core/network/yamibo/yamibo.dart';
import 'package:y300/features/library_shared/data/providers/sync_diagnostic_providers.dart';

final loggerProvider = Provider<Logger>((ref) {
  return Logger();
});

final cookieStoreProvider = Provider<CookieStore>((ref) {
  return CookieStore();
});

/// WebView → dio cookie 同步服务。默认基于 `flutter_inappwebview` 的全局
/// CookieManager，把 WebView 赢得的 WAF 通行证与登录态回灌到 dio 存储。
final webViewCookieSyncServiceProvider = Provider<WebViewCookieSyncService>((
  ref,
) {
  return WebViewCookieSyncService(
    cookieJar: InAppWebViewCookieJar(),
    cookieStore: ref.watch(cookieStoreProvider),
  );
});

/// WAF 挑战通过器：默认在离屏 [HeadlessInAppWebViewChallengePasser] 里
/// 让阿里云 arg1 挑战脚本自然执行完毕，从而把 acw_sc__v2 落到平台 cookie
/// jar。抽成 provider 便于测试替换。
final wafChallengePasserProvider = Provider<WafChallengePasser>((ref) {
  return HeadlessInAppWebViewChallengePasser();
});

/// WAF 挑战响应式恢复协调器。单例，跨请求共享放行窗口与去重状态。
/// 只要 [YamiboHttpGateway] 探测到挑战正文，就通过它统一走 headless
/// WebView → cookie 同步 → 重发流程。
final wafChallengeResolverProvider = Provider<WafChallengeResolver>((ref) {
  return WafChallengeResolver(
    challengePasser: ref.watch(wafChallengePasserProvider),
    cookieSyncService: ref.watch(webViewCookieSyncServiceProvider),
    siteUri: Uri.parse(AppConfig.siteBaseUrl),
  );
});

final yamiboSessionStoreProvider = Provider<YamiboSessionStore>((ref) {
  return YamiboSessionStore();
});

final yamiboSessionExtractorProvider = Provider<YamiboSessionExtractor>((ref) {
  return const YamiboSessionExtractor();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    cookieStore: ref.watch(cookieStoreProvider),
    logger: ref.watch(loggerProvider),
    diagnosticRecorder: ref.watch(syncDiagnosticRecorderProvider),
    sessionStore: ref.watch(yamiboSessionStoreProvider),
    sessionExtractor: ref.watch(yamiboSessionExtractorProvider),
    yamiboApiClient: ref.watch(yamiboApiClientProvider),
  );
});

final yamiboHttpGatewayProvider = Provider<YamiboHttpGateway>((ref) {
  return YamiboHttpGateway(
    cookieStore: ref.watch(cookieStoreProvider),
    logger: ref.watch(loggerProvider),
    diagnosticRecorder: ref.watch(syncDiagnosticRecorderProvider),
    sessionStore: ref.watch(yamiboSessionStoreProvider),
    sessionExtractor: ref.watch(yamiboSessionExtractorProvider),
    wafChallengeResolver: ref.watch(wafChallengeResolverProvider),
  );
});

final yamiboApiClientProvider = Provider<YamiboApiClient>((ref) {
  return YamiboApiClient(gateway: ref.watch(yamiboHttpGatewayProvider));
});

final yamiboHtmlClientProvider = Provider<YamiboHtmlClient>((ref) {
  return YamiboHtmlClient(gateway: ref.watch(yamiboHttpGatewayProvider));
});

final yamiboResourceClientProvider = Provider<YamiboResourceClient>((ref) {
  return YamiboResourceClient(gateway: ref.watch(yamiboHttpGatewayProvider));
});

final imageRequestHeaderBuilderProvider = Provider<ImageRequestHeaderBuilder>((
  ref,
) {
  return DiscuzImageRequestHeaderBuilder(
    cookieStore: ref.watch(cookieStoreProvider),
  );
});

final imageRequestHeaderBuilderForRefererProvider =
    Provider.family<ImageRequestHeaderBuilder, String?>((ref, referer) {
      final normalizedReferer = referer?.trim();
      return DiscuzImageRequestHeaderBuilder(
        cookieStore: ref.watch(cookieStoreProvider),
        referer: normalizedReferer == null || normalizedReferer.isEmpty
            ? '${AppConfig.siteBaseUrl}/'
            : normalizedReferer,
      );
    });
