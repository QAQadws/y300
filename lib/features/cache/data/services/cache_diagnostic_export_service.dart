import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:y300/features/cache/domain/models/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

class JsonCacheDiagnosticExportService implements CacheDiagnosticExportService {
  const JsonCacheDiagnosticExportService({
    required DownloadStorageService storageService,
    DateTime Function()? now,
  }) : _storageService = storageService,
       _now = now ?? DateTime.now;

  final DownloadStorageService _storageService;
  final DateTime Function() _now;

  @override
  Future<CacheDiagnosticExportResult> exportUsageReport(
    StorageUsageReport report,
  ) async {
    final exportedAt = _now();
    final root = await _storageService.prepareRoot();
    final diagnosticsDir = io.Directory(p.join(root.path, 'diagnostics'));
    await diagnosticsDir.create(recursive: true);
    final file = io.File(
      p.join(
        diagnosticsDir.path,
        'cache-diagnostics-${_formatFileTimestamp(exportedAt.toUtc())}.json',
      ),
    );
    final payload = <String, Object?>{
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'totalBytes': report.totalBytes,
      'calculatedAt': report.calculatedAt.toUtc().toIso8601String(),
      'sections': [
        for (final section in report.sections) _sectionPayload(section),
      ],
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      encoding: utf8,
      flush: true,
    );
    return CacheDiagnosticExportResult(
      path: file.path,
      totalBytes: report.totalBytes,
      sectionCount: report.sections.length,
      exportedAt: exportedAt,
    );
  }

  Map<String, Object?> _sectionPayload(StorageUsageSection section) {
    final labelRef =
        section.labelRef ??
        StorageUsageLabelRef(
          kind: StorageUsageLabelKind.bucket,
          code: section.bucket.id,
        );
    return <String, Object?>{
      'bucket': section.bucket.id,
      'labelKind': labelRef.kind.name,
      'labelCode': labelRef.code,
      'labelCount': labelRef.count,
      'labelQualifier': labelRef.qualifier,
      'bytes': section.bytes,
      'clearable': section.clearable,
      'categories': [
        for (final category in section.categories) _categoryPayload(category),
      ],
      'slices': [for (final slice in section.slices) _slicePayload(slice)],
    };
  }

  Map<String, Object?> _categoryPayload(StorageUsageCategory category) {
    final labelRef =
        category.labelRef ??
        StorageUsageLabelRef(
          kind: StorageUsageLabelKind.database,
          code: category.id,
        );
    return <String, Object?>{
      'id': category.id,
      'labelKind': labelRef.kind.name,
      'labelCode': labelRef.code,
      'labelCount': labelRef.count,
      'labelQualifier': labelRef.qualifier,
      'bytes': category.bytes,
      'clearable': category.clearable,
      'protected': category.protected,
    };
  }

  Map<String, Object?> _slicePayload(StorageUsageSlice slice) {
    final labelRef =
        slice.labelRef ??
        StorageUsageLabelRef(
          kind: StorageUsageLabelKind.database,
          code: slice.id,
        );
    return <String, Object?>{
      'id': slice.id,
      'labelKind': labelRef.kind.name,
      'labelCode': labelRef.code,
      'labelCount': labelRef.count,
      'labelQualifier': labelRef.qualifier,
      'bytes': slice.bytes,
      'protected': slice.protected,
    };
  }

  String _formatFileTimestamp(DateTime value) {
    return value.toIso8601String().replaceAll(':', '').replaceAll('.', '-');
  }
}
