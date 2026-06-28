import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/tags/data/repositories/forum_tag_repository.dart';
import 'package:y300/features/tags/data/repositories/yamibo_tag_thread_page_repository.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';

final forumTagRepositoryProvider = Provider<ForumTagRepository>((ref) {
  return const AssetForumTagRepository();
});

final forumTagLookupProvider = FutureProvider<ForumTagLookup>((ref) {
  return ref.watch(forumTagRepositoryProvider).loadLookup();
});

final yamiboTagThreadPageRepositoryProvider =
    Provider<YamiboTagThreadPageRepository>((ref) {
      return HtmlYamiboTagThreadPageRepository(
        htmlClient: ref.watch(yamiboHtmlClientProvider),
      );
    });
