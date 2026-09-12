import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/core/media/device_memory_profile.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_thumbnail_providers.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_thumbnail_writer.dart';

export 'library_cover_thumbnail_providers.dart';

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
    thumbnails: ref.watch(libraryCoverThumbnailCacheProvider),
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

final libraryCoverThumbnailWriterProvider =
    Provider<LibraryCoverThumbnailWriter>((ref) {
      final writer = LibraryCoverThumbnailWriter(
        cache: ref.watch(libraryCoverThumbnailCacheProvider),
        scheduler: ref.watch(libraryCoverDecodeSchedulerProvider),
        maxRetainedBytes:
            DeviceMemoryProfileStore.current?.isLowRamDevice == true
            ? 4 * 1024 * 1024
            : 8 * 1024 * 1024,
      );
      ref.onDispose(writer.dispose);
      return writer;
    });
