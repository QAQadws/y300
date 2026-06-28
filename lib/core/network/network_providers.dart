import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/yamibo/yamibo.dart';
import 'package:y300/features/library_shared/data/providers/sync_diagnostic_providers.dart';

final loggerProvider = Provider<Logger>((ref) {
  return Logger();
});

final cookieStoreProvider = Provider<CookieStore>((ref) {
  return CookieStore();
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
