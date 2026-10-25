import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/services/storage_accounting_service.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/fonts/data/services/font_library_storage_accounting_adapter.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_storage_usage.dart';

void main() {
  test('font files are one protected persistent-data contribution', () async {
    final usage = _Usage(12345);
    final report = await DefaultStorageAccountingService(
      adapters: [FontLibraryStorageAccountingAdapter(storageUsage: usage)],
    ).loadUsageReport();

    expect(usage.calls, 1);
    expect(report.totalBytes, 12345);
    final section = report.sections.single;
    expect(section.bucket, StorageBucket.fontLibrary);
    expect(section.labelRef?.kind, StorageUsageLabelKind.bucket);
    expect(section.labelRef?.code, 'font_library');
    expect(section.clearable, isFalse);
    expect(section.bytes, 12345);
    final slice = section.slices.single;
    expect(slice.id, 'font_library:protected');
    expect(slice.labelRef?.code, 'font_library');
    expect(slice.protected, isTrue);
    expect(slice.bytes, 12345);
  });

  test(
    'an unused library retains its category without phantom bytes',
    () async {
      final section = await FontLibraryStorageAccountingAdapter(
        storageUsage: _Usage(0),
      ).calculateUsage();

      expect(section.bucket, StorageBucket.fontLibrary);
      expect(section.bytes, 0);
      expect(section.clearable, isFalse);
      expect(section.slices, isEmpty);
    },
  );

  test('accounting failures are not converted to an empty library', () async {
    await expectLater(
      FontLibraryStorageAccountingAdapter(
        storageUsage: _Usage(0)..failure = StateError('unavailable'),
      ).calculateUsage(),
      throwsStateError,
    );
  });
}

final class _Usage implements FontLibraryStorageUsage {
  _Usage(this.bytes);
  final int bytes;
  int calls = 0;
  Object? failure;

  @override
  Future<int> calculateUsageBytes() async {
    calls++;
    if (failure case final error?) throw error;
    return bytes;
  }
}
