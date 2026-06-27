import 'package:y300/features/cache/domain/storage_usage_models.dart';

class CacheDiagnosticEvent {
  const CacheDiagnosticEvent({
    required this.event,
    required this.namespace,
    this.bucket,
    this.cacheKey,
    this.ownerType,
    this.ownerId,
    this.hit,
    this.reason,
    this.fields = const <String, Object?>{},
  });

  final String event;
  final CacheNamespace namespace;
  final StorageBucket? bucket;
  final String? cacheKey;
  final CacheOwnerType? ownerType;
  final String? ownerId;
  final bool? hit;
  final String? reason;
  final Map<String, Object?> fields;

  Map<String, Object?> toFields() {
    return <String, Object?>{
      'namespace': namespace.id,
      if (bucket != null) 'bucket': bucket!.id,
      if (cacheKey != null && cacheKey!.isNotEmpty) 'cacheKey': cacheKey,
      if (ownerType != null) 'ownerType': ownerType!.id,
      if (ownerId != null && ownerId!.isNotEmpty) 'ownerId': ownerId,
      if (hit != null) 'hit': hit,
      if (reason != null && reason!.isNotEmpty) 'reason': reason,
      ...fields,
    };
  }
}

abstract class CacheDiagnosticRecorder {
  void record(CacheDiagnosticEvent event);
}

class NoopCacheDiagnosticRecorder implements CacheDiagnosticRecorder {
  const NoopCacheDiagnosticRecorder();

  @override
  void record(CacheDiagnosticEvent event) {}
}

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
