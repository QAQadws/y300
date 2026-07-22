import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

class CacheDiagnosticExportResult {
  const CacheDiagnosticExportResult({
    required this.path,
    required this.totalBytes,
    required this.sectionCount,
    required this.exportedAt,
  });

  final String path;
  final int totalBytes;
  final int sectionCount;
  final DateTime exportedAt;
}

abstract class CacheDiagnosticExportService {
  Future<CacheDiagnosticExportResult> exportUsageReport(
    StorageUsageReport report,
  );
}
