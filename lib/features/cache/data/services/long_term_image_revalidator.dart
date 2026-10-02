import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/cache/data/providers/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';

/// Owns disk publication; FileService uses the existing forum resource transport.
class LongTermImageRevalidator implements ImageCacheRevalidator {
  LongTermImageRevalidator({
    required this.repository,
    required this.fileService,
    required this.directories,
    required this.mutations,
  });

  final ImageCacheRepository repository;
  final FileService fileService;
  final ImageCacheDirectoryResolver directories;
  final CacheMutationReporter mutations;
  final Map<
    String,
    ({Future<CachedImageResult> future, bool Function() current, String url})
  >
  _flights = {};

  @override
  Future<CachedImageResult> revalidate(
    ImageCacheRequest request, {
    bool Function()? isCurrent,
  }) {
    final previous = _flights[request.cacheKey];
    final current = isCurrent ?? () => true;
    if (previous != null) {
      if (previous.current() && previous.url == request.sourceUrl) {
        return previous.future;
      }
      return previous.future.then(
        (_) => current()
            ? revalidate(request, isCurrent: current)
            : CachedImageResult.failed,
      );
    }
    late final Future<CachedImageResult> flight;
    flight = _refresh(request, current).whenComplete(() {
      if (identical(_flights[request.cacheKey]?.future, flight)) {
        _flights.remove(request.cacheKey);
      }
    });
    _flights[request.cacheKey] = (
      future: flight,
      current: current,
      url: request.sourceUrl,
    );
    return flight;
  }

  Future<CachedImageResult> _refresh(
    ImageCacheRequest request,
    bool Function() current,
  ) async {
    try {
      final old = await repository.getByKey(request.cacheKey);
      final oldFile = old?.localPath == null ? null : File(old!.localPath!);
      final hasOld =
          oldFile != null &&
          await oldFile.exists() &&
          old?.contentHash != null &&
          sha256.convert(await oldFile.readAsBytes()).toString() ==
              old!.contentHash;
      if (!current()) return CachedImageResult.failed;
      final response = await fileService.get(
        request.sourceUrl,
        headers: {
          if (request.referer != null) 'Referer': request.referer!,
          if (hasOld &&
              old.lastSourceUrl == request.sourceUrl &&
              old.eTag != null)
            'If-None-Match': old.eTag!,
        },
      );
      if (response.statusCode == 304) {
        await response.content.drain<void>();
        return hasOld && current()
            ? _result(old, true)
            : CachedImageResult.failed;
      }
      if (response.statusCode != 200) {
        await response.content.drain<void>();
        return CachedImageResult.failed;
      }
      // Bound an unexpectedly large avatar before decoding it.
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in response.content) {
        if (!current() || buffer.length + chunk.length > 10 * 1024 * 1024) {
          return CachedImageResult.failed;
        }
        buffer.add(chunk);
      }
      final bytes = buffer.takeBytes();
      final hash = sha256.convert(bytes).toString();
      final now = DateTime.now();
      if (hasOld && hash == old.contentHash) {
        if (!current()) return CachedImageResult.failed;
        await repository.upsert(
          _record(
            request,
            old.localPath!,
            bytes.length,
            hash,
            response.eTag,
            now,
            old.createdAt,
          ),
        );
        return _result(old, true);
      }
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!current()) return CachedImageResult.failed;
      final directory = await directories.resolveLongTermDirectory();
      final keyHash = sha256.convert(utf8.encode(request.cacheKey)).toString();
      final target = File(p.join(directory, '$keyHash-$hash.img'));
      final temporary = File('${target.path}.pending');
      var published = false;
      var created = false;
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        if (!current()) return CachedImageResult.failed;
        if (await target.exists() &&
            sha256.convert(await target.readAsBytes()).toString() != hash) {
          await target.delete();
        }
        if (!await target.exists()) {
          await temporary.rename(target.path);
          created = true;
        }
        final record = _record(
          request,
          target.path,
          bytes.length,
          hash,
          response.eTag,
          now,
          old?.createdAt ?? now,
        );
        if (!current()) return CachedImageResult.failed;
        await repository.upsert(record);
        published = true;
        mutations.reportMutation(CacheNamespace.image);
        // Versioned paths prevent Flutter reusing old decoded bytes for a URL.
        if (hasOld &&
            oldFile.path != target.path &&
            p.isWithin(directory, oldFile.path)) {
          try {
            await oldFile.delete();
          } on Object {
            /* Best effort cleanup. */
          }
        }
        return _result(record, false);
      } finally {
        if (await temporary.exists()) await temporary.delete();
        if (!published && created && await target.exists()) {
          await target.delete();
        }
      }
    } on Object {
      return CachedImageResult.failed;
    }
  }

  CachedImageRecord _record(
    ImageCacheRequest request,
    String path,
    int bytes,
    String hash,
    String? eTag,
    DateTime now,
    DateTime createdAt,
  ) => CachedImageRecord(
    cacheKey: request.cacheKey,
    ownerType: request.ownerType.dbValue,
    ownerId: request.ownerId,
    role: request.role.dbValue,
    lastSourceUrl: request.sourceUrl,
    localPath: path,
    bytes: bytes,
    contentHash: hash,
    eTag: eTag,
    protected: false,
    retentionClass: ImageRetentionClass.sticky,
    createdAt: createdAt,
    updatedAt: now,
    lastAccessedAt: now,
  );

  CachedImageResult _result(CachedImageRecord record, bool fromCache) =>
      CachedImageResult(
        success: true,
        cacheKey: record.cacheKey,
        localPath: record.localPath,
        bytes: record.bytes,
        fromCache: fromCache,
      );
}
