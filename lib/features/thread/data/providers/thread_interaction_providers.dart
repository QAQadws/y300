import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';

final threadPostRatingPreparationProvider =
    Provider<ThreadPostRatingPreparationRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).postRatingPreparation!;
    });

final threadPostRatingCommandProvider = Provider<ThreadPostRatingCommand>((
  ref,
) {
  return ref.watch(yamiboForumClientProvider).postRatingCommand!;
});

final threadPostCommentPreparationProvider =
    Provider<ThreadPostCommentPreparationRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).postCommentPreparation!;
    });

final threadPostCommentCommandProvider = Provider<ThreadPostCommentCommand>((
  ref,
) {
  return ref.watch(yamiboForumClientProvider).postCommentCommand!;
});
