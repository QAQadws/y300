import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

final favoriteForumDirectoryRepositoryProvider =
    Provider<FavoriteForumDirectoryRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).favoriteForumDirectory!;
    });

final favoriteThreadDirectoryRepositoryProvider =
    Provider<FavoriteThreadDirectoryRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).favoriteThreadDirectory!;
    });

final favoriteForumCommandProvider = Provider<FavoriteForumCommand>((ref) {
  return ref.watch(yamiboForumClientProvider).favoriteForumCommand!;
});

final favoriteThreadCommandProvider = Provider<FavoriteThreadCommand>((ref) {
  return ref.watch(yamiboForumClientProvider).favoriteThreadCommand!;
});
