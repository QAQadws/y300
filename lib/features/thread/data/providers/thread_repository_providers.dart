import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

/// Native thread details remain HTML-first in production.
final threadRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ThreadDetailHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
    documentCacheService: ref.watch(documentCacheServiceProvider),
    snapshotCacheService: ref.watch(parsedSnapshotCacheServiceProvider),
  );
});

/// Structured v4 reads used by comic/favorite adapters.
final threadJsonRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ApiThreadRepository(ref.watch(apiClientProvider));
});

final threadPostLocatorProvider = Provider<ThreadPostLocator>((ref) {
  return HtmlThreadPostLocator(gateway: ref.watch(yamiboHttpGatewayProvider));
});
