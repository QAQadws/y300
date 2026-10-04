import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_reader_service.dart';

class NetworkComicReaderService implements ComicReaderService {
  NetworkComicReaderService({
    required ComicEpisodeCatalogRepository episodeCatalogRepository,
    ImageCacheService? imageCacheService,
    required BaseCacheManager cacheManager,
    String? imageReferer,
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _episodeCatalogRepository = episodeCatalogRepository,
       _imageCacheService = imageCacheService,
       _cacheManager = cacheManager,
       _imageReferer = imageReferer,
       _urlResolver = urlResolver;

  final ComicEpisodeCatalogRepository _episodeCatalogRepository;
  final ImageCacheService? _imageCacheService;
  final BaseCacheManager _cacheManager;
  final String? _imageReferer;
  final SiteUrlResolver _urlResolver;

  @override
  Future<ComicEpisodeImagesFetchResult> fetchEpisodeImages(String tid) async {
    final result = await _episodeCatalogRepository.loadCatalog(
      ComicEpisodeCatalogRequest(sourceTid: tid),
    );
    return result.when(
      success: (catalog, _, _) => ComicEpisodeImagesFetched(
        catalog.images.map((image) => image.url).toList(growable: false),
      ),
      failure: (failure) => ComicEpisodeImagesFetchFailed(
        reason: _mapDataReadFailureReason(failure.kind),
        message: failure.diagnosticMessage,
      ),
    );
  }

  ComicEpisodeImagesFetchFailureReason _mapDataReadFailureReason(
    DataReadFailureKind type,
  ) {
    return switch (type) {
      DataReadFailureKind.network ||
      DataReadFailureKind.timeout ||
      DataReadFailureKind.cancelled =>
        ComicEpisodeImagesFetchFailureReason.network,
      DataReadFailureKind.unauthorized =>
        ComicEpisodeImagesFetchFailureReason.auth,
      DataReadFailureKind.server => ComicEpisodeImagesFetchFailureReason.server,
      DataReadFailureKind.parse => ComicEpisodeImagesFetchFailureReason.parse,
      DataReadFailureKind.business ||
      DataReadFailureKind.unsupported ||
      DataReadFailureKind.unknown =>
        ComicEpisodeImagesFetchFailureReason.unknown,
    };
  }

  @override
  Future<ComicImageCacheResult> cacheImage({
    required String imageUrl,
    String? cacheKey,
    ImageCacheOwnerType? ownerType,
    String? ownerId,
    ImageCacheRole role = ImageCacheRole.comicPage,
    String? episodeId,
    int? imageIndex,
    bool protected = false,
  }) async {
    final sourceUrl = _urlResolver.resolve(imageUrl) ?? imageUrl.trim();
    final normalizedKey = cacheKey?.trim();
    final cacheService = _imageCacheService;
    if (cacheService != null &&
        normalizedKey != null &&
        normalizedKey.isNotEmpty &&
        ownerType != null &&
        ownerId != null &&
        ownerId.trim().isNotEmpty) {
      final result = await cacheService.ensureCached(
        ImageCacheRequest(
          cacheKey: normalizedKey,
          sourceUrl: sourceUrl,
          ownerType: ownerType,
          ownerId: ownerId,
          role: role,
          episodeId: episodeId,
          imageIndex: imageIndex,
          protected: protected,
          referer: _imageReferer,
        ),
      );
      return ComicImageCacheResult(
        success: result.success,
        localPath: result.localPath,
        cacheKey: result.cacheKey,
        bytes: result.bytes,
        fromCache: result.fromCache,
      );
    }

    try {
      final fileInfo = await _cacheManager.downloadFile(
        sourceUrl,
        key: normalizedKey == null || normalizedKey.isEmpty
            ? sourceUrl
            : normalizedKey,
        authHeaders: _imageReferer?.trim().isEmpty == false
            ? <String, String>{'Referer': _imageReferer!.trim()}
            : null,
      );
      return ComicImageCacheResult(
        success: true,
        localPath: fileInfo.file.path,
        cacheKey: normalizedKey == null || normalizedKey.isEmpty
            ? sourceUrl
            : normalizedKey,
        bytes: await fileInfo.file.length(),
      );
    } catch (_) {
      return const ComicImageCacheResult(success: false);
    }
  }

  @override
  Future<void> prefetchImages({required List<String> imageUrls}) async {
    for (final imageUrl in imageUrls) {
      await cacheImage(imageUrl: imageUrl);
    }
  }
}
