import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart'
    as forum_adapters;
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';

/// Composition-root regression guard. Adapter behavior itself is verified by
/// the package contract suites; this file only locks Y300's production plan.
void main() {
  test('native thread detail remains HTML-first', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final client = container.read(yamiboForumClientProvider);
    expect(container.read(threadRepositoryProvider), same(client.threadDetail));
    expect(
      client.threadDetail,
      isA<forum_adapters.ThreadDetailHtmlRepository>(),
    );
  });

  test('ingestion and comic reads remain fixed to v4 adapters', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final client = container.read(yamiboForumClientProvider);
    expect(
      container.read(threadIngestionRepositoryProvider),
      same(client.threadIngestionDetail),
    );
    expect(
      client.threadIngestionDetail,
      isA<forum_adapters.ApiThreadRepository>(),
    );
    expect(
      container.read(comicEpisodeCatalogRepositoryProvider),
      same(client.comicEpisodeCatalog),
    );
    expect(
      client.comicEpisodeCatalog,
      isA<forum_adapters.DiscuzApiComicEpisodeCatalogRepository>(),
    );
    expect(
      container.read(comicThreadDiscoveryRepositoryProvider),
      same(client.comicThreadDiscovery),
    );
    expect(
      client.comicThreadDiscovery,
      isA<forum_adapters.ThreadRepositoryComicThreadDiscoveryAdapter>(),
    );
    expect(
      container.read(threadReplyPageRepositoryProvider),
      same(client.threadReplyPage),
    );
    expect(
      client.threadReplyPage,
      isA<forum_adapters.ApiThreadReplyPageRepository>(),
    );
  });
}
