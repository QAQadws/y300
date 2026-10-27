import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/favorites/data/providers/favorite_parse_providers.dart';
import 'package:y300/features/favorites/data/providers/favorite_directory_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/thread/domain/services/thread_favorite_action_service.dart';

final threadFavoriteActionServiceProvider =
    Provider<ThreadFavoriteActionService>((ref) {
      final shelfRefreshBus = ref.watch(libraryShelfRefreshBusProvider);
      final owner = ref.watch(verifiedSessionOwnerProvider);
      return DefaultThreadFavoriteActionService(
        command: ref.watch(favoriteThreadCommandProvider),
        enqueueFavoriteParse: ({required receipt, title}) async {
          if (owner == null ||
              ref.read(verifiedSessionOwnerProvider) != owner) {
            throw StateError('favorite_parse_owner_changed');
          }
          await ref
              .read(favoriteParseServiceProvider)
              .requestConfirmed(receipt, title: title);
        },
        notifyFavoriteModule: ({required String reason, required String tid}) {
          shelfRefreshBus.notify(
            modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
            reason: reason,
            source: LibraryMutationSource.threadFavoriteAction,
            tid: tid,
          );
        },
      );
    });
