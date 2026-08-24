import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/yamibo_forum_client_host_adapters.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/auth/data/providers/auth_formhash_provider.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';

export 'yamibo_forum_transport_providers.dart';

typedef Y300ThreadDetailHtmlDecoder =
    ThreadDetailData Function(
      String html, {
      required String fallbackTid,
      required int fallbackPage,
      String fallbackSubject,
    });

typedef Y300ThreadDetailApiDecoder =
    ThreadDetailData Function(
      Map<String, dynamic> variables, {
      required int page,
    });

Y300ThreadDetailHtmlDecoder createY300ThreadDetailHtmlDecoder() {
  final parser = ThreadDetailHtmlParser(
    siteOrigin: Uri.parse(AppConfig.siteBaseUrl),
  );
  return (
    html, {
    required fallbackTid,
    required fallbackPage,
    fallbackSubject = '',
  }) => parser.parse(
    html,
    fallbackTid: fallbackTid,
    fallbackPage: fallbackPage,
    fallbackSubject: fallbackSubject,
  );
}

Y300ThreadDetailApiDecoder createY300ThreadDetailApiDecoder() {
  const mapper = ThreadDetailApiMapper();
  return (variables, {required page}) =>
      mapper.mapVariables(variables, page: page);
}

final yamiboThreadDetailHtmlDecoderProvider =
    Provider<Y300ThreadDetailHtmlDecoder>((ref) {
      return createY300ThreadDetailHtmlDecoder();
    });

final yamiboThreadDetailApiDecoderProvider =
    Provider<Y300ThreadDetailApiDecoder>((ref) {
      return createY300ThreadDetailApiDecoder();
    });

/// Process-wide package facade. Y300 intentionally injects its shared host
/// transport so reads, commands, Cookie state, and WAF recovery stay on one
/// application-owned session path.
final yamiboForumClientProvider = Provider<YamiboForumClient>((ref) {
  return YamiboForumClientBuilder(
    config: ref.watch(yamiboForumClientConfigProvider),
    network: ref.watch(yamiboForumClientNetworkProvider),
    sessionStore: ref.watch(yamiboForumSessionStoreProvider),
    documentStore: ref.watch(yamiboForumDocumentStoreProvider),
    snapshotStore: ref.watch(yamiboForumSnapshotStoreProvider),
    formhashProvider: ref.watch(yamiboForumFormhashProvider),
    stickerCatalogStore: ref.watch(yamiboForumStickerCatalogStoreProvider),
  ).buildStandardReads();
});

final yamiboForumFormhashProvider = Provider<ForumFormhashProvider>((ref) {
  return Y300ForumFormhashAdapter(ref.watch(formhashProvider));
});

final yamiboForumSessionStoreProvider = Provider<ForumSessionStore>((ref) {
  return Y300ForumSessionAdapter(ref.watch(yamiboSessionStoreProvider));
});

final yamiboForumDocumentStoreProvider = Provider<ForumDocumentStore>((ref) {
  return Y300ForumDocumentStoreAdapter(ref.watch(documentCacheServiceProvider));
});

final yamiboForumSnapshotStoreProvider = Provider<ForumSnapshotStore>((ref) {
  return Y300ForumSnapshotStoreAdapter(
    ref.watch(parsedSnapshotCacheServiceProvider),
  );
});

final yamiboForumStickerCatalogStoreProvider =
    Provider<ForumStickerCatalogStore>((ref) {
      return const Y300ForumStickerCatalogStore();
    });
