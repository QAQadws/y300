import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:y300/features/cache/domain/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
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
        for (final section in report.sections)
          <String, Object?>{
            'bucket': section.bucket.id,
            'label': section.label,
            'bytes': section.bytes,
            'clearable': section.clearable,
            'slices': [
              for (final slice in section.slices)
                <String, Object?>{
                  'id': slice.id,
                  'label': slice.label,
                  'bytes': slice.bytes,
                  'protected': slice.protected,
                },
            ],
          },
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

  String _formatFileTimestamp(DateTime value) {
    return value.toIso8601String().replaceAll(':', '').replaceAll('.', '-');
  }
}
