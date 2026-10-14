import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:logger/logger.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/cache/data/services/y300_forum_resource_file_service.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';

/// Internal stages used to locate failures without exposing resource identity.
enum ImageCacheDiagnosticStage {
  validation,
  indexRead,
  managerInitialization,
  cacheLookup,
  fileInspection,
  download,
  indexWrite,
  decode,
}

/// Privacy-safe failure groups emitted by the image cache boundary.
enum ImageCacheDiagnosticFailureKind {
  invalidRequest,
  network,
  timeout,
  unauthorized,
  notFound,
  server,
  securityChallenge,
  invalidContent,
  redirectRejected,
  cancelled,
  fileSystem,
  cacheManager,
  indexStore,
  decode,
  unsupported,
  unknown,
}

/// A diagnostic event that intentionally contains no URL, path, or payload.
final class ImageCacheFailureDiagnostic {
  const ImageCacheFailureDiagnostic({
    required this.stage,
    required this.ownerType,
    required this.role,
    required this.cacheKeyFingerprint,
    required this.failureKind,
    required this.reasonCode,
    required this.exceptionType,
    required this.elapsedMilliseconds,
    this.bytesReceived,
  });

  final ImageCacheDiagnosticStage stage;
  final String ownerType;
  final String role;
  final String cacheKeyFingerprint;
  final ImageCacheDiagnosticFailureKind failureKind;
  final String reasonCode;
  final String exceptionType;
  final int elapsedMilliseconds;
  final int? bytesReceived;

  static String fingerprint(String cacheKey) {
    final digest = sha256.convert(utf8.encode(cacheKey.trim())).toString();
    return digest.substring(0, 16);
  }
}

/// Records internal cache failures. Production defaults to the no-op variant.
abstract interface class ImageCacheDiagnosticRecorder {
  void recordFailure(ImageCacheFailureDiagnostic event);
}

final class NoopImageCacheDiagnosticRecorder
    implements ImageCacheDiagnosticRecorder {
  const NoopImageCacheDiagnosticRecorder();

  @override
  void recordFailure(ImageCacheFailureDiagnostic event) {}
}

/// Debug logger that passively groups repeated, already sanitized failures.
/// A hit never extends its window; no timer retains or flushes diagnostics.
final class LoggerImageCacheDiagnosticRecorder
    implements ImageCacheDiagnosticRecorder {
  LoggerImageCacheDiagnosticRecorder(
    this._logger, {
    DateTime Function()? now,
    Duration suppressionWindow = const Duration(seconds: 30),
    int maxBuckets = 256,
  }) : assert(!suppressionWindow.isNegative),
       assert(maxBuckets >= 0),
       _now = now ?? DateTime.now,
       _suppressionWindow = suppressionWindow,
       _maxBuckets = maxBuckets;

  final Logger _logger;
  final DateTime Function() _now;
  final Duration _suppressionWindow;
  final int _maxBuckets;
  final _buckets = <_ImageCacheLogGroup, _ImageCacheLogWindow>{};
  DateTime? _lastObservedAt;

  @override
  void recordFailure(ImageCacheFailureDiagnostic event) {
    try {
      var suppressedCount = 0;
      DateTime? now;
      _ImageCacheLogGroup? group;
      if (_maxBuckets > 0 && _suppressionWindow > Duration.zero) {
        now = _now();
        group = (
          fingerprint: event.cacheKeyFingerprint,
          stage: event.stage,
          kind: event.failureKind,
          reason: event.reasonCode,
          exceptionType: event.exceptionType,
          ownerType: event.ownerType,
          role: event.role,
        );
        final previous = _buckets[group];
        if (_lastObservedAt != null && now.isBefore(_lastObservedAt!)) {
          // A wall-clock correction retires every old window. Preserve only
          // this group's count for its immediate replacement message.
          _buckets.clear();
        }
        _lastObservedAt = now;
        final current = _buckets[group];
        if (current != null &&
            now.difference(current.startedAt) < _suppressionWindow) {
          current.suppressedCount++;
          return;
        }
        suppressedCount = previous?.suppressedCount ?? 0;
      }
      final receivedBytes = event.bytesReceived;
      _logger.w(
        '[ImageCache][failure] '
        'stage=${event.stage.name} '
        'ownerType=${event.ownerType} '
        'role=${event.role} '
        'cacheKeyHash=${event.cacheKeyFingerprint} '
        'kind=${event.failureKind.name} '
        'reason=${event.reasonCode} '
        'exception=${event.exceptionType} '
        '${receivedBytes == null ? '' : 'bytesReceived=$receivedBytes '}'
        'elapsedMs=${event.elapsedMilliseconds}'
        '${suppressedCount > 0 ? ' suppressedCount=$suppressedCount' : ''}',
      );
      if (group != null && now != null) {
        _buckets.remove(group);
        while (_buckets.length >= _maxBuckets) {
          _buckets.remove(_buckets.keys.first);
        }
        _buckets[group] = _ImageCacheLogWindow(now);
      }
    } catch (_) {
      // Diagnostics must never become part of the image-loading outcome.
    }
  }
}

typedef _ImageCacheLogGroup = ({
  String fingerprint,
  ImageCacheDiagnosticStage stage,
  ImageCacheDiagnosticFailureKind kind,
  String reason,
  String exceptionType,
  String ownerType,
  String role,
});

final class _ImageCacheLogWindow {
  _ImageCacheLogWindow(this.startedAt);

  final DateTime startedAt;
  int suppressedCount = 0;
}

/// Builds a stable diagnostic classification without inspecting error text.
ImageCacheFailureDiagnostic buildImageCacheFailureDiagnostic({
  required ImageCacheDiagnosticStage stage,
  required String cacheKey,
  required ImageCacheOwnerType? ownerType,
  required ImageCacheRole? role,
  required Object error,
  required Duration elapsed,
  String? reasonCode,
}) {
  final classification = _classifyFailure(stage, error);
  return ImageCacheFailureDiagnostic(
    stage: stage,
    ownerType: ownerType?.dbValue ?? 'unknown',
    role: role?.dbValue ?? 'unknown',
    cacheKeyFingerprint: ImageCacheFailureDiagnostic.fingerprint(cacheKey),
    failureKind: classification.kind,
    reasonCode: reasonCode ?? classification.reasonCode,
    exceptionType: error.runtimeType.toString(),
    elapsedMilliseconds: elapsed.inMilliseconds,
    bytesReceived: classification.bytesReceived,
  );
}

({ImageCacheDiagnosticFailureKind kind, String reasonCode, int? bytesReceived})
_classifyFailure(ImageCacheDiagnosticStage stage, Object error) {
  if (error is ForumResourceFileServiceException) {
    return _resourceClassification(error.failure);
  }
  if (error is ForumResourceStreamException) {
    final value = _resourceClassification(error.failure);
    return (
      kind: value.kind,
      reasonCode: value.reasonCode,
      bytesReceived: error.bytesReceived,
    );
  }
  if (error is TimeoutException) {
    return (
      kind: ImageCacheDiagnosticFailureKind.timeout,
      reasonCode: 'cache_timeout',
      bytesReceived: null,
    );
  }
  if (error is io.FileSystemException) {
    return (
      kind: ImageCacheDiagnosticFailureKind.fileSystem,
      reasonCode: 'cache_file_system',
      bytesReceived: null,
    );
  }
  return switch (stage) {
    ImageCacheDiagnosticStage.validation => (
      kind: ImageCacheDiagnosticFailureKind.invalidRequest,
      reasonCode: 'cache_request_invalid',
      bytesReceived: null,
    ),
    ImageCacheDiagnosticStage.indexRead ||
    ImageCacheDiagnosticStage.indexWrite => (
      kind: ImageCacheDiagnosticFailureKind.indexStore,
      reasonCode: 'cache_index_failure',
      bytesReceived: null,
    ),
    ImageCacheDiagnosticStage.managerInitialization ||
    ImageCacheDiagnosticStage.cacheLookup => (
      kind: ImageCacheDiagnosticFailureKind.cacheManager,
      reasonCode: 'cache_manager_failure',
      bytesReceived: null,
    ),
    ImageCacheDiagnosticStage.fileInspection => (
      kind: ImageCacheDiagnosticFailureKind.fileSystem,
      reasonCode: 'cache_file_inspection_failure',
      bytesReceived: null,
    ),
    ImageCacheDiagnosticStage.decode => (
      kind: ImageCacheDiagnosticFailureKind.decode,
      reasonCode: 'cache_image_decode_failure',
      bytesReceived: null,
    ),
    ImageCacheDiagnosticStage.download => (
      kind: ImageCacheDiagnosticFailureKind.unknown,
      reasonCode: 'cache_download_failure',
      bytesReceived: null,
    ),
  };
}

({ImageCacheDiagnosticFailureKind kind, String reasonCode, int? bytesReceived})
_resourceClassification(ForumResourceFailure failure) {
  final kind = switch (failure.kind) {
    ForumResourceFailureKind.invalidReference =>
      ImageCacheDiagnosticFailureKind.invalidRequest,
    ForumResourceFailureKind.unsupported =>
      ImageCacheDiagnosticFailureKind.unsupported,
    ForumResourceFailureKind.network => ImageCacheDiagnosticFailureKind.network,
    ForumResourceFailureKind.timeout => ImageCacheDiagnosticFailureKind.timeout,
    ForumResourceFailureKind.unauthorized =>
      ImageCacheDiagnosticFailureKind.unauthorized,
    ForumResourceFailureKind.notFound =>
      ImageCacheDiagnosticFailureKind.notFound,
    ForumResourceFailureKind.server => ImageCacheDiagnosticFailureKind.server,
    ForumResourceFailureKind.securityChallenge =>
      ImageCacheDiagnosticFailureKind.securityChallenge,
    ForumResourceFailureKind.invalidContent =>
      ImageCacheDiagnosticFailureKind.invalidContent,
    ForumResourceFailureKind.redirectRejected =>
      ImageCacheDiagnosticFailureKind.redirectRejected,
    ForumResourceFailureKind.cancelled =>
      ImageCacheDiagnosticFailureKind.cancelled,
    ForumResourceFailureKind.unknown => ImageCacheDiagnosticFailureKind.unknown,
  };
  return (kind: kind, reasonCode: failure.code, bytesReceived: null);
}
