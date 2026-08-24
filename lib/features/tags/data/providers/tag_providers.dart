import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/tags/data/repositories/forum_tag_repository.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/repositories/forum_tag_directory_repository.dart';

final forumTagRepositoryProvider = Provider<ForumTagRepository>((ref) {
  return const AssetForumTagRepository();
});

final forumTagLookupProvider = FutureProvider<ForumTagLookup>((ref) {
  return ref.watch(forumTagRepositoryProvider).loadLookup();
});

final forumTagDirectoryRepositoryProvider =
    Provider<ForumTagDirectoryRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).forumTagDirectory!;
    });
