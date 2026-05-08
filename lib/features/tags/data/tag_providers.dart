import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/tags/data/forum_tag_repository.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';

final forumTagRepositoryProvider = Provider<ForumTagRepository>((ref) {
  return const AssetForumTagRepository();
});

final forumTagLookupProvider = FutureProvider<ForumTagLookup>((ref) {
  return ref.watch(forumTagRepositoryProvider).loadLookup();
});
