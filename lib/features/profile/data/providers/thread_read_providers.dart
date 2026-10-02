import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/threads/my_thread_controller.dart';

final userThreadDirectoryRepositoryProvider =
    Provider<UserThreadDirectoryRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).userThreadDirectory!;
    });

final myThreadControllerProvider = Provider.autoDispose
    .family<MyThreadController, MyThreadPageArgs>((ref, args) {
      // The owner includes the session revision, so logging into the same UID
      // again also disposes old retained content and invalidates pending reads.
      final owner = ref.watch(verifiedProfileOwnerProvider);
      final controller = MyThreadController(
        repository: ref.watch(userThreadDirectoryRepositoryProvider),
        accountId: owner?.uid,
        args: args,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });
