import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

import '../../domain/repositories/font_library_storage_usage.dart';

final class FontLibraryStorageAccountingAdapter
    implements StorageAccountingAdapter {
  const FontLibraryStorageAccountingAdapter({
    required FontLibraryStorageUsage storageUsage,
  }) : _storageUsage = storageUsage;

  final FontLibraryStorageUsage _storageUsage;

  @override
  StorageBucket get bucket => StorageBucket.fontLibrary;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final bytes = await _storageUsage.calculateUsageBytes();
    final label = StorageUsageLabelRef(
      kind: StorageUsageLabelKind.bucket,
      code: bucket.id,
    );
    return StorageUsageSection(
      bucket: bucket,
      labelRef: label,
      bytes: bytes,
      clearable: false,
      slices: [
        if (bytes > 0)
          StorageUsageSlice(
            id: '${bucket.id}:protected',
            labelRef: label,
            bytes: bytes,
            protected: true,
          ),
      ],
    );
  }
}
