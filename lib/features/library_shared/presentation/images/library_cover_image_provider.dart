import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_decode_policy.dart';
import 'package:y300/features/library_shared/data/services/library_cover_thumbnail_store.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_thumbnail_writer.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_load_trace.dart';

enum LibraryCoverUsage { shelf, detail, original }

@immutable
class LibraryCoverImageKey {
  const LibraryCoverImageKey({
    required this.assetId,
    required this.revision,
    required this.decodeTarget,
    this.usage = LibraryCoverUsage.shelf,
  });

  final String assetId;
  final int revision;
  final LibraryCoverDecodeTarget decodeTarget;
  final LibraryCoverUsage usage;

  int? get targetWidthPx => decodeTarget.targetWidthPx;

  int? get targetHeightPx => decodeTarget.targetHeightPx;

  bool get isOriginal => decodeTarget.isOriginal;

  @override
  bool operator ==(Object other) {
    return other is LibraryCoverImageKey &&
        other.assetId == assetId &&
        other.revision == revision &&
        other.decodeTarget == decodeTarget &&
        other.usage == usage;
  }

  @override
  int get hashCode => Object.hash(assetId, revision, decodeTarget, usage);
}

class LibraryCoverImageProvider extends ImageProvider<LibraryCoverImageKey> {
  const LibraryCoverImageProvider({
    required this.asset,
    required this.decodeTarget,
    this.usage = LibraryCoverUsage.shelf,
    required this.store,
    required this.scheduler,
    this.thumbnails,
    this.thumbnailWriter,
  });

  final LibraryCoverAssetRef asset;
  final LibraryCoverDecodeTarget decodeTarget;
  final LibraryCoverUsage usage;
  final LibraryCoverStore store;
  final LibraryCoverDecodeScheduler scheduler;
  final LibraryCoverThumbnailStore? thumbnails;
  final LibraryCoverThumbnailWriter? thumbnailWriter;

  LibraryCoverImageKey get cacheKey => LibraryCoverImageKey(
    assetId: asset.assetId,
    revision: asset.revision,
    decodeTarget: decodeTarget,
    usage: decodeTarget.isOriginal ? LibraryCoverUsage.original : usage,
  );

  @override
  Future<LibraryCoverImageKey> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<LibraryCoverImageKey>(cacheKey);
  }

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    LibraryCoverImageKey key,
    ImageErrorListener handleError,
  ) {
    final thumbnailKey = _thumbnailKey(key);
    if (thumbnailKey != null) thumbnails?.registerTarget(thumbnailKey);
    if (LibraryCoverLoadTrace.enabled) {
      final status = PaintingBinding.instance.imageCache.statusForKey(key);
      if (status.keepAlive || status.live) {
        LibraryCoverLoadTrace(
          sha256
              .convert(utf8.encode(asset.assetId))
              .toString()
              .substring(0, 16),
          key.targetWidthPx,
          key.targetHeightPx,
        ).mark('memoryHit');
      }
    }
    super.resolveStreamForKey(configuration, stream, key, handleError);
  }

  @override
  ImageStreamCompleter loadImage(
    LibraryCoverImageKey key,
    ImageDecoderCallback decode,
  ) {
    final state = _CoverLoadState();
    final thumbnailKey = _thumbnailKey(key);
    if (thumbnailKey != null) thumbnails?.registerTarget(thumbnailKey);
    final trace = LibraryCoverLoadTrace(
      LibraryCoverLoadTrace.enabled
          ? sha256
                .convert(utf8.encode(asset.assetId))
                .toString()
                .substring(0, 16)
          : '',
      key.targetWidthPx,
      key.targetHeightPx,
    );
    late final _CoverImageStreamCompleter completer;
    completer = _CoverImageStreamCompleter(
      codec: _loadCodec(key, decode, thumbnailKey, state, trace),
      onRelease: () => state.disposed = true,
      onFirstImage: (image) {
        trace.mark('firstFrame');
        if (state.derivative && thumbnailKey != null) {
          thumbnails?.scheduleMaintenance(thumbnailKey);
        }
        final ticket = state.ticket;
        if (thumbnailKey != null &&
            ticket != null &&
            state.generateThumbnail &&
            image.image.colorSpace == ui.ColorSpace.sRGB) {
          thumbnailWriter?.enqueue(
            key: thumbnailKey,
            ticket: ticket,
            image: image.image,
            isActive: () => completer.hasConsumers,
          );
        }
      },
      scale: 1,
      debugLabel: '${asset.assetId}@${asset.revision}:$decodeTarget',
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<LibraryCoverAssetRef>('asset', asset),
        DiagnosticsProperty<LibraryCoverDecodeTarget>(
          'decodeTarget',
          decodeTarget,
        ),
      ],
    );
    completer.addOnLastListenerRemovedCallback(() {
      thumbnailWriter?.discardInactive();
    });
    return completer;
  }

  LibraryCoverThumbnailKey? _thumbnailKey(LibraryCoverImageKey key) =>
      key.usage != LibraryCoverUsage.shelf || key.isOriginal
      ? null
      : LibraryCoverThumbnailKey(
          asset: asset,
          width: key.targetWidthPx!,
          height: key.targetHeightPx!,
        );

  Future<ui.Codec> _loadCodec(
    LibraryCoverImageKey key,
    ImageDecoderCallback decode,
    LibraryCoverThumbnailKey? thumbnailKey,
    _CoverLoadState state,
    LibraryCoverLoadTrace trace,
  ) async {
    final cache = thumbnails;
    if (thumbnailKey != null && cache != null) {
      state.ticket = cache.ticket(thumbnailKey);
      final thumbnail = await cache.lookup(thumbnailKey);
      trace.mark('thumbnailLookup');
      if (thumbnail != null) {
        try {
          final codec = await _decodeFirstFrame(
            thumbnail,
            key,
            decode,
            state,
            trace,
            derivative: true,
          );
          trace.mark('thumbnailHit');
          return codec;
        } catch (_) {
          if (state.disposed) rethrow;
          // Never invalidate the protected original because a derivative broke.
          if (state.ticket?.isValid == true) {
            final removal = cache.remove(thumbnailKey);
            // Renew only our own invalidation, before yielding to a concurrent
            // clear/purge. A stale request may display, but must never write.
            state.ticket = cache.ticket(thumbnailKey);
            await removal.catchError((Object _) {});
          }
        }
      }
    }
    var candidate = asset;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      if (state.disposed) throw StateError('Cover request disposed');
      var fileReady = false;
      try {
        final file = await store.ensureAvailable(candidate);
        fileReady = true;
        trace.mark('originalFileReady');
        return await _decodeFirstFrame(
          file,
          key,
          decode,
          state,
          trace,
          derivative: false,
        );
      } catch (error, stackTrace) {
        final canRepair =
            attempt == 0 &&
            !state.disposed &&
            fileReady &&
            asset.sourceUrl?.trim().isNotEmpty == true;
        if (canRepair) {
          final canRenewTicket = state.ticket?.isValid == true;
          final invalidation = store.invalidate(asset);
          // LocalLibraryCoverStore invalidates derivative tickets synchronously.
          // Do not acquire a fresh generation after awaiting the disk cleanup.
          if (canRenewTicket && thumbnailKey != null && cache != null) {
            state.ticket = cache.ticket(thumbnailKey);
          }
          await invalidation;
          candidate = asset.copyWith(clearLegacyLocalPath: true);
          continue;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    throw StateError('Unreachable cover decode state');
  }

  Future<ui.Codec> _decodeFirstFrame(
    io.File file,
    LibraryCoverImageKey key,
    ImageDecoderCallback decode,
    _CoverLoadState state,
    LibraryCoverLoadTrace trace, {
    required bool derivative,
  }) {
    trace.mark(
      'decodeQueued',
      active: scheduler.activeCount,
      pending: scheduler.pendingCount,
    );
    return scheduler.schedule(
      key: key,
      action: () async {
        if (state.disposed) throw StateError('Cover request disposed');
        trace.mark('decodeStart');
        ui.Codec? codec;
        var sampled = false;
        try {
          final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
          trace.mark('fileRead', bytes: buffer.length);
          // ImageDecoderCallback takes ownership of the buffer, including errors.
          codec = await decode(
            buffer,
            getTargetSize: (width, height) {
              if (derivative) return const ui.TargetImageSize();
              final size = _targetSize(width, height);
              sampled =
                  (size.width ?? width) < width ||
                  (size.height ?? height) < height;
              return size;
            },
          );
          final frame = await codec.getNextFrame();
          if (state.disposed) {
            frame.image.dispose();
            throw StateError('Cover request disposed');
          }
          state.derivative = derivative;
          state.generateThumbnail =
              !derivative &&
              key.usage == LibraryCoverUsage.shelf &&
              !key.isOriginal &&
              sampled &&
              codec.frameCount == 1;
          trace.mark('decoded');
          return _FirstFrameCodec(codec, frame);
        } catch (_) {
          codec?.dispose();
          rethrow;
        }
      },
    );
  }

  ui.TargetImageSize _targetSize(int intrinsicWidth, int intrinsicHeight) {
    final decodedSize = LibraryCoverDecodePolicy.resolveDecodedSize(
      target: decodeTarget,
      intrinsicWidth: intrinsicWidth,
      intrinsicHeight: intrinsicHeight,
    );
    if (decodedSize == null) {
      return const ui.TargetImageSize();
    }
    return ui.TargetImageSize(
      width: decodedSize.width.toInt(),
      height: decodedSize.height.toInt(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LibraryCoverImageProvider && other.cacheKey == cacheKey;
  }

  @override
  int get hashCode => cacheKey.hashCode;
}

class _CoverLoadState {
  bool disposed = false;
  bool generateThumbnail = false;
  bool derivative = false;
  LibraryCoverThumbnailTicket? ticket;
}

class _CoverImageStreamCompleter extends MultiFrameImageStreamCompleter {
  _CoverImageStreamCompleter({
    required super.codec,
    required super.scale,
    super.debugLabel,
    super.informationCollector,
    required this.onFirstImage,
    required this.onRelease,
  });

  final void Function(ImageInfo) onFirstImage;
  final void Function() onRelease;
  bool _reported = false;

  bool get hasConsumers => hasListeners;

  @override
  void onDisposed() {
    onRelease();
    super.onDisposed();
  }

  @override
  void setImage(ImageInfo image) {
    super.setImage(image);
    if (!_reported) {
      _reported = true;
      // A consumer may synchronously detach/dispose during super.setImage.
      if (hasListeners) onFirstImage(image);
    }
  }
}

/// Transfers the already-decoded first frame to Flutter without decoding twice.
class _FirstFrameCodec implements ui.Codec {
  _FirstFrameCodec(this._codec, this._first);
  final ui.Codec _codec;
  ui.FrameInfo? _first;
  bool _disposed = false;

  @override
  int get frameCount => _codec.frameCount;
  @override
  int get repetitionCount => _codec.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() {
    final first = _first;
    _first = null;
    return first == null ? _codec.getNextFrame() : SynchronousFuture(first);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _first?.image.dispose();
    _first = null;
    _codec.dispose();
  }
}
