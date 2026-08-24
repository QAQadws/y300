import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo_forum_client_host_adapters.dart';

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
