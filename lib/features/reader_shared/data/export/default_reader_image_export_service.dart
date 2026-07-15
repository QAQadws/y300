import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';

class DefaultReaderImageExportService implements ReaderImageExportService {
  DefaultReaderImageExportService({
    required ImageCacheService imageCacheService,
    required ReaderImageExportSink sink,
  }) : _imageCacheService = imageCacheService,
       _sink = sink;

  final ImageCacheService _imageCacheService;
  final ReaderImageExportSink _sink;
  final Map<String, Future<ReaderImageExportResult>> _inFlight =
      <String, Future<ReaderImageExportResult>>{};

  @override
  Future<ReaderImageExportResult> export(ReaderImageExportRequest request) {
    final identity = _requestIdentity(request);
    final existing = _inFlight[identity];
    if (existing != null) {
      return existing;
    }
    late final Future<ReaderImageExportResult> task;
    task = _exportSafely(request).whenComplete(() {
      if (identical(_inFlight[identity], task)) {
        _inFlight.remove(identity);
      }
    });
    _inFlight[identity] = task;
    return task;
  }

  Future<ReaderImageExportResult> _exportSafely(
    ReaderImageExportRequest request,
  ) async {
    try {
      return await _export(request);
    } on Object catch (error) {
      // Keep the application service total: a cache or platform implementation
      // must never turn a toolbar action into an unhandled Future error.
      return ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.mediaWriteFailed,
        message: error.toString(),
      );
    }
  }

  Future<ReaderImageExportResult> _export(
    ReaderImageExportRequest request,
  ) async {
    late final CachedImageResult cached;
    try {
      cached = await _imageCacheService.ensureCached(request.cacheRequest);
    } on Object catch (error) {
      return ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.cacheUnavailable,
        message: error.toString(),
      );
    }
    final localPath = cached.localPath?.trim();
    if (!cached.success || localPath == null || localPath.isEmpty) {
      return const ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.cacheUnavailable,
      );
    }

    final file = File(localPath);
    late final ReaderImageExportFormat? format;
    try {
      if (!await file.exists()) {
        return const ReaderImageExportResult.failure(
          ReaderImageExportFailureReason.cacheUnavailable,
        );
      }
      format = await ReaderImageExportFormatResolver.resolve(
        file: file,
        sourceUrl: request.cacheRequest.sourceUrl,
      );
    } on Object catch (error) {
      return ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.cacheUnavailable,
        message: error.toString(),
      );
    }
    if (format == null) {
      return const ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.unsupportedFormat,
      );
    }

    final displayName = ReaderImageExportFileName.sanitize(
      request.metadata.baseName,
      extension: format.extension,
    );
    try {
      final destination = await _sink.save(
        sourcePath: file.path,
        displayName: displayName,
        mimeType: format.mimeType,
        albumName: request.metadata.albumName,
      );
      return ReaderImageExportResult.success(destination);
    } on ReaderImageExportException catch (error) {
      return ReaderImageExportResult.failure(
        error.reason,
        message: error.message,
      );
    } on Object catch (error) {
      return ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.mediaWriteFailed,
        message: error.toString(),
      );
    }
  }

  String _requestIdentity(ReaderImageExportRequest request) {
    final cacheKey = request.cacheRequest.cacheKey.trim();
    return '$cacheKey\n${request.cacheRequest.sourceUrl}\n'
        '${request.metadata.baseName}';
  }
}

class ReaderImageExportFormat {
  const ReaderImageExportFormat({
    required this.mimeType,
    required this.extension,
  });

  final String mimeType;
  final String extension;
}

class ReaderImageExportFormatResolver {
  const ReaderImageExportFormatResolver._();

  static Future<ReaderImageExportFormat?> resolve({
    required File file,
    required String sourceUrl,
  }) async {
    final header = await _readHeader(file);
    if (_startsWith(header, const <int>[0xFF, 0xD8, 0xFF])) {
      return const ReaderImageExportFormat(
        mimeType: 'image/jpeg',
        extension: 'jpg',
      );
    }
    if (_startsWith(header, const <int>[0x89, 0x50, 0x4E, 0x47])) {
      return const ReaderImageExportFormat(
        mimeType: 'image/png',
        extension: 'png',
      );
    }
    if (_startsWith(header, const <int>[0x47, 0x49, 0x46, 0x38])) {
      return const ReaderImageExportFormat(
        mimeType: 'image/gif',
        extension: 'gif',
      );
    }
    if (_startsWith(header, const <int>[0x52, 0x49, 0x46, 0x46]) &&
        header.length >= 12 &&
        String.fromCharCodes(header.sublist(8, 12)) == 'WEBP') {
      return const ReaderImageExportFormat(
        mimeType: 'image/webp',
        extension: 'webp',
      );
    }

    final extension = p
        .extension(Uri.tryParse(sourceUrl)?.path ?? '')
        .toLowerCase()
        .replaceFirst('.', '');
    return switch (extension) {
      'jpg' || 'jpeg' => const ReaderImageExportFormat(
        mimeType: 'image/jpeg',
        extension: 'jpg',
      ),
      'png' => const ReaderImageExportFormat(
        mimeType: 'image/png',
        extension: 'png',
      ),
      'gif' => const ReaderImageExportFormat(
        mimeType: 'image/gif',
        extension: 'gif',
      ),
      'webp' => const ReaderImageExportFormat(
        mimeType: 'image/webp',
        extension: 'webp',
      ),
      _ => null,
    };
  }

  static Future<List<int>> _readHeader(File file) async {
    final bytes = <int>[];
    await for (final chunk in file.openRead(0, 16)) {
      bytes.addAll(chunk);
      if (bytes.length >= 16) {
        break;
      }
    }
    return bytes;
  }

  static bool _startsWith(List<int> value, List<int> prefix) {
    if (value.length < prefix.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (value[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }
}

class ReaderImageExportFileName {
  const ReaderImageExportFileName._();

  static String sanitize(String baseName, {required String extension}) {
    var value = baseName.trim();
    value = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    value = value.replaceFirst(RegExp(r'\.$'), '_');
    if (value.isEmpty) {
      value = 'Y300-image';
    }
    if (value.length > 96) {
      value = value.substring(0, 96).trimRight();
    }
    final suffix = '.$extension';
    if (!value.toLowerCase().endsWith(suffix)) {
      value += suffix;
    }
    return value;
  }
}
