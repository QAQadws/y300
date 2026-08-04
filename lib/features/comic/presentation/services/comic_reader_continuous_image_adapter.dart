import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

class ComicReaderContinuousImageAdapter {
  const ComicReaderContinuousImageAdapter();

  List<ContinuousImageItem> mapImages({
    required String episodeId,
    required List<ComicReaderImageState> images,
  }) {
    return images
        .map((image) => mapImage(episodeId: episodeId, image: image))
        .toList(growable: false);
  }

  ContinuousImageItem mapImage({
    required String episodeId,
    required ComicReaderImageState image,
  }) {
    final cacheKey = image.cacheKey?.trim();
    final effectiveCacheKey = cacheKey == null || cacheKey.isEmpty
        ? image.imageUrl
        : cacheKey;
    return ContinuousImageItem(
      ownerId: episodeId,
      id: '$episodeId:${image.imageIndex}:$effectiveCacheKey',
      url: image.imageUrl,
      cacheKey: effectiveCacheKey,
      index: image.imageIndex,
      sourceKind: ContinuousImageSourceKind.comicPage,
      knownWidth: image.width,
      knownHeight: image.height,
      knownDimensionSource: ContinuousImageDimensionSource.persistedCache,
      fallbackAspectRatio: 3 / 4,
    );
  }
}
