import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/core/media/device_memory_profile.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';

final libraryCoverDirectoryResolverProvider =
    Provider<LibraryCoverDirectoryResolver>((ref) {
      return const LibraryCoverDirectoryResolver();
    });

final libraryCoverDownloaderProvider = Provider<LibraryCoverDownloader>((ref) {
  return ForumResourceLibraryCoverDownloader(
    resourceClient: ref.watch(yamiboForumResourceClientProvider),
    referenceResolver: ref.watch(yamiboForumResourceReferenceResolverProvider),
    referer: ref.watch(forumImageRefererProvider),
  );
});

final libraryCoverStoreProvider = Provider<LibraryCoverStore>((ref) {
  final resolver = ref.watch(libraryCoverDirectoryResolverProvider);
  return LocalLibraryCoverStore(
    rootPath: resolver.resolveRoot(),
    downloader: ref.watch(libraryCoverDownloaderProvider),
  );
});

final libraryCoverDecodeSchedulerProvider =
    Provider<LibraryCoverDecodeScheduler>((ref) {
      return LibraryCoverDecodeScheduler(
        maxConcurrent: DeviceMemoryProfileStore.current?.isLowRamDevice == true
            ? 2
            : 3,
      );
    });
