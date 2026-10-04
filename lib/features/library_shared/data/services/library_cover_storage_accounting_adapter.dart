import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/data/services/library_cover_thumbnail_store.dart';

class LibraryCoverStorageAccountingAdapter implements StorageAccountingAdapter {
  const LibraryCoverStorageAccountingAdapter({
    required LibraryCoverStore store,
    LibraryCoverThumbnailStore? thumbnails,
  }) : _store = store,
       _thumbnails = thumbnails;

  final LibraryCoverStore _store;
  final LibraryCoverThumbnailStore? _thumbnails;

  @override
  StorageBucket get bucket => StorageBucket.libraryCover;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final bytes =
        await _store.calculateUsageBytes() +
        (await _thumbnails?.calculateUsageBytes() ?? 0);
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: bytes,
      clearable: false,
      slices: <StorageUsageSlice>[
        if (bytes > 0)
          StorageUsageSlice(
            id: 'library_cover:protected',
            labelRef: StorageUsageLabelRef(
              kind: StorageUsageLabelKind.bucket,
              code: bucket.id,
            ),
            bytes: bytes,
            protected: true,
          ),
      ],
    );
  }
}
