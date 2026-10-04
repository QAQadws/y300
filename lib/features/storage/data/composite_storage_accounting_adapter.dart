import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

/// Combines contributions to one displayed bucket without measuring data again.
class CompositeStorageAccountingAdapter implements StorageAccountingAdapter {
  const CompositeStorageAccountingAdapter({
    required this.bucket,
    required List<StorageAccountingAdapter> adapters,
  }) : _adapters = adapters;

  @override
  final StorageBucket bucket;
  final List<StorageAccountingAdapter> _adapters;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final sections = <StorageUsageSection>[];
    for (final adapter in _adapters) {
      if (adapter.bucket != bucket) {
        throw StateError('Storage contribution belongs to another bucket.');
      }
      sections.add(await adapter.calculateUsage());
    }
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: sections.fold<int>(0, (total, section) => total + section.bytes),
      clearable: sections.any((section) => section.clearable),
      // Zero-byte count slices are meaningful metadata and must be preserved.
      slices: sections
          .expand((section) => section.slices)
          .toList(growable: false),
      categories: sections
          .expand((section) => section.categories)
          .toList(growable: false),
    );
  }
}
