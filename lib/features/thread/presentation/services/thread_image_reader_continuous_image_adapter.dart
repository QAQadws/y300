import 'package:continuous_image_geometry/continuous_image_geometry.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_layout_hint.dart';

const _sourceIndexKey = 'indexInPost';

extension ThreadImageReaderSourceIndex on ContinuousImageItem {
  int get indexInPost => switch (extra[_sourceIndexKey]) {
    final int sourceIndex => sourceIndex,
    _ => index,
  };
}

class ThreadImageReaderContinuousImageAdapter {
  const ThreadImageReaderContinuousImageAdapter();

  List<ContinuousImageItem> mapRequest(
    ThreadImageOpenRequest request, {
    double fallbackAspectRatio = 0.7,
  }) {
    final ownerId = _ownerIdFor(request);
    return request.group.entries.indexed
        .map((indexed) {
          final (index, entry) = indexed;
          return _mapEntry(
            ownerId: ownerId,
            entry: entry,
            galleryIndex: index,
            referer: request.referer,
            fallbackAspectRatio: fallbackAspectRatio,
          );
        })
        .toList(growable: false);
  }

  ContinuousImageItem _mapEntry({
    required String ownerId,
    required ThreadPostImageEntry entry,
    required int galleryIndex,
    required String referer,
    required double fallbackAspectRatio,
  }) {
    final dimensions = _dimensionsFor(entry.layoutHint);
    return ContinuousImageItem(
      ownerId: ownerId,
      id: '$ownerId:${entry.indexInPost}:${entry.cacheKey}',
      url: entry.url,
      cacheKey: entry.cacheKey,
      // Scrolling and seeking use the dense gallery position. Source identity
      // survives filtering for cache work, export and return to the body.
      index: galleryIndex,
      sourceKind: ContinuousImageSourceKind.threadImageReader,
      referer: Uri.tryParse(referer),
      knownWidth: dimensions?.width,
      knownHeight: dimensions?.height,
      knownDimensionSource: dimensions?.source,
      fallbackAspectRatio: fallbackAspectRatio,
      extra: <String, Object?>{
        _sourceIndexKey: entry.indexInPost,
        'rawUrl': entry.rawUrl,
        if (entry.aid != null) 'aid': entry.aid,
      },
    );
  }

  String _ownerIdFor(ThreadImageOpenRequest request) {
    return request.sourceOwnerId;
  }

  _ThreadImageReaderDimensions? _dimensionsFor(
    ThreadPostBlockImageLayoutHint? hint,
  ) {
    if (hint == null || hint.aspectRatio <= 0 || !hint.aspectRatio.isFinite) {
      return null;
    }
    const syntheticHeight = 1000;
    return _ThreadImageReaderDimensions(
      width: (hint.aspectRatio * syntheticHeight).round(),
      height: syntheticHeight,
      source: _mapHintSource(hint.source),
    );
  }

  ContinuousImageDimensionSource _mapHintSource(
    ThreadPostResourceLayoutHintSource source,
  ) {
    switch (source) {
      case ThreadPostResourceLayoutHintSource.htmlAttribute:
        return ContinuousImageDimensionSource.html;
      case ThreadPostResourceLayoutHintSource.cachedDimension:
        return ContinuousImageDimensionSource.persistedCache;
      case ThreadPostResourceLayoutHintSource.contentDefault:
        return ContinuousImageDimensionSource.fallback;
    }
  }
}

class _ThreadImageReaderDimensions {
  const _ThreadImageReaderDimensions({
    required this.width,
    required this.height,
    required this.source,
  });

  final int width;
  final int height;
  final ContinuousImageDimensionSource source;
}
