import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_decode_policy.dart';

@immutable
class LibraryCoverImageKey {
  const LibraryCoverImageKey({
    required this.assetId,
    required this.revision,
    required this.decodeTarget,
  });

  final String assetId;
  final int revision;
  final LibraryCoverDecodeTarget decodeTarget;

  int? get targetWidthPx => decodeTarget.targetWidthPx;

  int? get targetHeightPx => decodeTarget.targetHeightPx;

  bool get isOriginal => decodeTarget.isOriginal;

  @override
  bool operator ==(Object other) {
    return other is LibraryCoverImageKey &&
        other.assetId == assetId &&
        other.revision == revision &&
        other.decodeTarget == decodeTarget;
  }

  @override
  int get hashCode => Object.hash(assetId, revision, decodeTarget);
}

class LibraryCoverImageProvider extends ImageProvider<LibraryCoverImageKey> {
  const LibraryCoverImageProvider({
    required this.asset,
    required this.decodeTarget,
    required this.store,
    required this.scheduler,
  });

  final LibraryCoverAssetRef asset;
  final LibraryCoverDecodeTarget decodeTarget;
  final LibraryCoverStore store;
  final LibraryCoverDecodeScheduler scheduler;

  LibraryCoverImageKey get cacheKey => LibraryCoverImageKey(
    assetId: asset.assetId,
    revision: asset.revision,
    decodeTarget: decodeTarget,
  );

  @override
  Future<LibraryCoverImageKey> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<LibraryCoverImageKey>(cacheKey);
  }

  @override
  ImageStreamCompleter loadImage(
    LibraryCoverImageKey key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(key, decode),
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
  }

  Future<ui.Codec> _loadCodec(
    LibraryCoverImageKey key,
    ImageDecoderCallback decode,
  ) async {
    var candidate = asset;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      var fileReady = false;
      try {
        final file = await store.ensureAvailable(candidate);
        fileReady = true;
        return scheduler.schedule(
          key: key,
          action: () async {
            final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
            return decode(
              buffer,
              getTargetSize: (intrinsicWidth, intrinsicHeight) {
                return _targetSize(intrinsicWidth, intrinsicHeight);
              },
            );
          },
        );
      } catch (error, stackTrace) {
        final canRepair =
            attempt == 0 &&
            fileReady &&
            asset.sourceUrl?.trim().isNotEmpty == true;
        if (canRepair) {
          await store.invalidate(asset);
          candidate = asset.copyWith(clearLegacyLocalPath: true);
          continue;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    throw StateError('Unreachable cover decode state');
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
