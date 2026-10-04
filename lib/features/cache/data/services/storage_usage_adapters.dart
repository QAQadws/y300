import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';

class ImageCacheStorageAccountingAdapter implements StorageAccountingAdapter {
  const ImageCacheStorageAccountingAdapter({
    required ImageCacheRepository repository,
  }) : _repository = repository;

  final ImageCacheRepository _repository;

  @override
  StorageBucket get bucket => StorageBucket.imageCache;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final groups = await _repository.calculateUsageGroups();
    final slices = groups
        .map((group) {
          return StorageUsageSlice(
            id: group.id,
            labelRef: StorageUsageLabelRef(
              kind: StorageUsageLabelKind.imageRole,
              code: group.role,
              qualifier: group.retentionClass,
            ),
            bytes: group.bytes,
            protected: group.protected,
          );
        })
        .where((slice) => slice.bytes > 0)
        .toList();
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.bytes);
    final categories = _imageCategories(groups);
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: total,
      clearable: slices.any((slice) => !slice.protected),
      slices: slices,
      categories: categories,
    );
  }

  List<StorageUsageCategory> _imageCategories(
    List<ImageCacheUsageGroup> groups,
  ) {
    var clearable = 0;
    var sticky = 0;
    var protectedAssets = 0;
    for (final group in groups) {
      if (group.bytes <= 0) {
        continue;
      }
      if (group.protected ||
          group.retentionClass == ImageRetentionClass.protected.dbValue ||
          group.retentionClass == ImageRetentionClass.downloaded.dbValue) {
        protectedAssets += group.bytes;
      } else if (group.retentionClass == ImageRetentionClass.sticky.dbValue) {
        sticky += group.bytes;
      } else {
        clearable += group.bytes;
      }
    }
    return <StorageUsageCategory>[
      StorageUsageCategory(
        id: 'clearable',
        labelRef: const StorageUsageLabelRef(
          kind: StorageUsageLabelKind.imageCategory,
          code: 'clearable',
        ),
        bytes: clearable,
        clearable: true,
        protected: false,
      ),
      StorageUsageCategory(
        id: 'sticky',
        labelRef: const StorageUsageLabelRef(
          kind: StorageUsageLabelKind.imageCategory,
          code: 'sticky',
        ),
        bytes: sticky,
        clearable: false,
        protected: false,
      ),
      StorageUsageCategory(
        id: 'protected',
        labelRef: const StorageUsageLabelRef(
          kind: StorageUsageLabelKind.imageCategory,
          code: 'protected',
        ),
        bytes: protectedAssets,
        clearable: false,
        protected: true,
      ),
    ].where((category) => category.bytes > 0).toList(growable: false);
  }
}

class PageCacheStorageAccountingAdapter implements StorageAccountingAdapter {
  const PageCacheStorageAccountingAdapter({
    required DocumentCacheService documentCacheService,
    ParsedSnapshotCacheService? snapshotCacheService,
  }) : _documentCacheService = documentCacheService,
       _snapshotCacheService = snapshotCacheService;

  final DocumentCacheService _documentCacheService;
  final ParsedSnapshotCacheService? _snapshotCacheService;

  @override
  StorageBucket get bucket => StorageBucket.pageCache;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final documentSection = await _documentCacheService.calculateUsage();
    final snapshotSection = await _snapshotCacheService?.calculateUsage();
    final sections = <StorageUsageSection>[documentSection, ?snapshotSection];
    final slices = sections
        .expand((section) => section.slices)
        .where((slice) => slice.bytes > 0)
        .toList(growable: false);
    final total = sections.fold<int>(0, (sum, section) => sum + section.bytes);
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: total,
      clearable: slices.any((slice) => !slice.protected),
      slices: slices,
    );
  }
}
