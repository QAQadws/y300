import 'package:y300/features/cache/domain/storage_usage_models.dart';

class DefaultStorageAccountingService implements StorageAccountingService {
  const DefaultStorageAccountingService({
    required List<StorageAccountingAdapter> adapters,
    DateTime Function()? now,
  }) : _adapters = adapters,
       _now = now ?? DateTime.now;

  final List<StorageAccountingAdapter> _adapters;
  final DateTime Function() _now;

  @override
  Future<StorageUsageReport> loadUsageReport() async {
    final sections = <StorageUsageSection>[];
    for (final adapter in _adapters) {
      sections.add(await adapter.calculateUsage());
    }
    return StorageUsageReport.fromSections(
      sections: sections,
      calculatedAt: _now(),
    );
  }
}
