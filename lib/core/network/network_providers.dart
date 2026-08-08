import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/waf/waf.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import 'package:y300/core/network/yamibo/yamibo.dart';

final loggerProvider = Provider<Logger>((ref) {
  return Logger();
});

final cookieStoreProvider = Provider<CookieStore>((ref) {
  return CookieStore();
});

/// WebView → dio cookie 同步服务。默认基于 `flutter_inappwebview` 的全局
/// CookieManager，把 WebView 里赢得的登录态 cookie 回灌到 dio 存储。
final webViewCookieSyncServiceProvider = Provider<WebViewCookieSyncService>((
  ref,
) {
  return WebViewCookieSyncService(
    cookieJar: InAppWebViewCookieJar(),
    cookieStore: ref.watch(cookieStoreProvider),
  );
});

/// Process-wide bridge between challenged native requests and the single
/// background WebView mounted by the application root.
final wafChallengeRecoveryCoordinatorProvider =
    Provider<WafChallengeRecoveryCoordinator>((ref) {
      return WafChallengeRecoveryCoordinator();
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
    sessionStore: ref.watch(yamiboSessionStoreProvider),
    sessionExtractor: ref.watch(yamiboSessionExtractorProvider),
    yamiboApiClient: ref.watch(yamiboApiClientProvider),
  );
});

final yamiboHttpGatewayProvider = Provider<YamiboHttpGateway>((ref) {
  return YamiboHttpGateway(
    cookieStore: ref.watch(cookieStoreProvider),
    logger: ref.watch(loggerProvider),
    sessionStore: ref.watch(yamiboSessionStoreProvider),
    sessionExtractor: ref.watch(yamiboSessionExtractorProvider),
    wafChallengeRecoveryCoordinator: ref.watch(
      wafChallengeRecoveryCoordinatorProvider,
    ),
  );
});

/// Native clearance check used while the background WAF WebView is still
/// mounted. It deliberately delegates to the shared gateway transport so it
/// uses the same CookieStore and User-Agent without invoking recovery again.
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
