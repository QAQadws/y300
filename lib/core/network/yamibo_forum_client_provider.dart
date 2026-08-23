import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/config/app_config.dart';

/// Explicit, non-production facade wiring for the 4-A client boundary.
/// Existing feature providers continue to use YamiboHttpGateway until 4-B.
final yamiboForumClientProvider = Provider<YamiboForumClient>((ref) {
  final cookies = MemoryForumCookieStore();
  final config = ForumClientConfig(
    siteOrigin: Uri.parse(AppConfig.siteBaseUrl),
    apiOrigin: Uri.parse(AppConfig.apiBaseUrl),
    userAgent: 'Y300/${AppConfig.siteBaseUrl}',
  );
  return YamiboForumClient(
    config: config,
    network: DioForumClientNetwork(config: config, cookies: cookies),
  );
});
