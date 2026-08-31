import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
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
    final threadDetail = client.threadDetail;
    expect(threadDetail, isNotNull);
    expect(container.read(threadRepositoryProvider), same(threadDetail));
    expect(
      threadDetail!.capabilities.values.supports(
        ThreadDetailCapability.ratingAction,
      ),
      isTrue,
    );
  });

  test('ingestion and comic reads remain fixed to v4 adapters', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final client = container.read(yamiboForumClientProvider);
    final threadIngestionDetail = client.threadIngestionDetail;
    final comicEpisodeCatalog = client.comicEpisodeCatalog;
    final comicThreadDiscovery = client.comicThreadDiscovery;
    expect(threadIngestionDetail, isNotNull);
    expect(comicEpisodeCatalog, isNotNull);
    expect(comicThreadDiscovery, isNotNull);
    expect(
      container.read(threadIngestionRepositoryProvider),
      same(threadIngestionDetail),
    );
    expect(
      threadIngestionDetail!.capabilities.values.supports(
        ThreadDetailCapability.attachmentMetadata,
      ),
      isTrue,
    );
    expect(
      container.read(comicEpisodeCatalogRepositoryProvider),
      same(comicEpisodeCatalog),
    );
    expect(
      comicEpisodeCatalog!.capabilities.supports(
        ComicEpisodeCatalogCapability.stableSourceIdentity,
      ),
      isTrue,
    );
    expect(
      container.read(comicThreadDiscoveryRepositoryProvider),
      same(comicThreadDiscovery),
    );
    expect(comicThreadDiscovery!.capabilities.values, isNotNull);
    expect(
      container.read(threadReplyPageRepositoryProvider),
      same(client.threadReplyPage),
    );
  });
}
