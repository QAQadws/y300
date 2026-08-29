import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';

final threadReplyPreparationProvider =
    Provider<ThreadReplyPreparationRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).threadReplyPreparation!;
    });

final threadReplyCommandProvider = Provider<ThreadReplyCommand>((ref) {
  return ref.watch(yamiboForumClientProvider).threadReplyCommand!;
});
