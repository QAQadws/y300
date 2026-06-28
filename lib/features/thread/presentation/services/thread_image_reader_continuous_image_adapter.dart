import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';

class ThreadImageReaderContinuousImageAdapter {
  const ThreadImageReaderContinuousImageAdapter();

  List<ContinuousImageItem> mapRequest(
    ThreadImageOpenRequest request, {
    double fallbackAspectRatio = 0.7,
    double spacingAfter = 10,
  }) {
    final ownerId = _ownerIdFor(request);
    return request.group.entries
        .map(
          (entry) => mapEntry(
            ownerId: ownerId,
            entry: entry,
            referer: request.referer,
            fallbackAspectRatio: fallbackAspectRatio,
            spacingAfter: spacingAfter,
          ),
        )
        .toList(growable: false);
  }

  ContinuousImageItem mapEntry({
    required String ownerId,
    required ThreadPostImageEntry entry,
    required String referer,
    required double fallbackAspectRatio,
    required double spacingAfter,
  }) {
    final dimensions = _dimensionsFor(entry.layoutHint);
    return ContinuousImageItem(
      ownerId: ownerId,
      id: '$ownerId:${entry.indexInPost}:${entry.cacheKey}',
      url: entry.url,
      cacheKey: entry.cacheKey,
      index: entry.indexInPost,
      sourceKind: ContinuousImageSourceKind.threadImageReader,
      referer: Uri.tryParse(referer),
      knownWidth: dimensions?.width,
      knownHeight: dimensions?.height,
      knownDimensionSource: dimensions?.source,
      fallbackAspectRatio: fallbackAspectRatio,
      spacingAfter: spacingAfter,
      extra: <String, Object?>{
        'rawUrl': entry.rawUrl,
        if (entry.aid != null) 'aid': entry.aid,
      },
    );
  }

  String _ownerIdFor(ThreadImageOpenRequest request) {
    return 'thread:${request.tid}:post:${request.pid}';
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
