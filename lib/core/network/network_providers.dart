import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/library_shared/data/sync_diagnostic_providers.dart';

final loggerProvider = Provider<Logger>((ref) {
  return Logger();
});

final cookieStoreProvider = Provider<CookieStore>((ref) {
  return CookieStore();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    cookieStore: ref.watch(cookieStoreProvider),
    logger: ref.watch(loggerProvider),
    diagnosticRecorder: ref.watch(syncDiagnosticRecorderProvider),
  );
});

final imageRequestHeaderBuilderProvider = Provider<ImageRequestHeaderBuilder>((ref) {
  return DiscuzImageRequestHeaderBuilder(
    cookieStore: ref.watch(cookieStoreProvider),
  );
});
