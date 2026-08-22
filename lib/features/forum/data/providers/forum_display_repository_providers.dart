import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/forum/data/repositories/forum_display_repository.dart';
import 'package:y300/features/forum/domain/repositories/forum_display_repository.dart';

/// Parsed forum display remains HTML-first in production.
final forumDisplayRepositoryProvider = Provider<ForumDisplayRepository>((ref) {
  return ForumDisplayHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
    sessionStore: ref.watch(yamiboSessionStoreProvider),
    documentCacheService: ref.watch(documentCacheServiceProvider),
    snapshotCacheService: ref.watch(parsedSnapshotCacheServiceProvider),
  );
});
