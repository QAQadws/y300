import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Parsed forum display remains HTML-first in production.
final forumDisplayRepositoryProvider = Provider<ForumDisplayRepository>((ref) {
  return ref.watch(yamiboForumClientProvider).forumDisplay!;
});
