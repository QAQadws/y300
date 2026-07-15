import 'package:y300/features/cache/domain/models/image_cache_models.dart';

enum ReaderImageExportPlatform { android, ios, unsupported }

class ReaderImageExportMetadata {
  const ReaderImageExportMetadata({required this.baseName, this.albumName});

  final String baseName;
  final String? albumName;
}

class ReaderImageExportRequest {
  const ReaderImageExportRequest({
    required this.cacheRequest,
    required this.metadata,
  });

  final ImageCacheRequest cacheRequest;
  final ReaderImageExportMetadata metadata;
}

class ReaderImageExportDestination {
  const ReaderImageExportDestination({
    required this.platform,
    required this.locator,
    required this.displayLocation,
  });

  final ReaderImageExportPlatform platform;

  /// Android content URI or iOS PhotoKit asset local identifier.
  final String locator;
  final String displayLocation;
}

enum ReaderImageExportFailureReason {
  cacheUnavailable,
  permissionDenied,
  permissionRestricted,
  unsupportedPlatform,
  unsupportedFormat,
  mediaWriteFailed,
}

class ReaderImageExportResult {
  const ReaderImageExportResult._({
    required this.success,
    this.destination,
    this.failureReason,
    this.message,
  });

  const ReaderImageExportResult.success(
    ReaderImageExportDestination destination,
  ) : this._(success: true, destination: destination);

  const ReaderImageExportResult.failure(
    ReaderImageExportFailureReason reason, {
    String? message,
  }) : this._(success: false, failureReason: reason, message: message);

  final bool success;
  final ReaderImageExportDestination? destination;
  final ReaderImageExportFailureReason? failureReason;
  final String? message;
}

class ReaderImageExportException implements Exception {
  const ReaderImageExportException(this.reason, [this.message]);

  final ReaderImageExportFailureReason reason;
  final String? message;

  @override
  String toString() {
    final detail = message;
    return detail == null || detail.isEmpty
        ? 'ReaderImageExportException($reason)'
        : 'ReaderImageExportException($reason): $detail';
  }
}

abstract interface class ReaderImageExportSink {
  Future<ReaderImageExportDestination> save({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    String? albumName,
  });
}

abstract interface class ReaderImageExportService {
  Future<ReaderImageExportResult> export(ReaderImageExportRequest request);
}
