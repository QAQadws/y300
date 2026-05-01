import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

class ComicReaderArgs {
  const ComicReaderArgs({
    required this.comicId,
    required this.episodeId,
  });

  final String comicId;
  final String episodeId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ComicReaderArgs &&
        other.comicId == comicId &&
        other.episodeId == episodeId;
  }

  @override
  int get hashCode => Object.hash(comicId, episodeId);
}

class ComicReaderImageState {
  const ComicReaderImageState({
    required this.imageUrl,
    required this.imageIndex,
    required this.cacheStatus,
    this.cacheLocalPath,
    this.failed = false,
  });

  final String imageUrl;
  final int imageIndex;
  final String cacheStatus;
  final String? cacheLocalPath;
  final bool failed;

  ComicReaderImageState copyWith({
    String? cacheStatus,
    String? cacheLocalPath,
    bool? failed,
  }) {
    return ComicReaderImageState(
      imageUrl: imageUrl,
      imageIndex: imageIndex,
      cacheStatus: cacheStatus ?? this.cacheStatus,
      cacheLocalPath: cacheLocalPath ?? this.cacheLocalPath,
      failed: failed ?? this.failed,
    );
  }
}

class ComicReaderViewState {
  const ComicReaderViewState({
    required this.comicId,
    required this.episodeId,
    required this.episodeTitle,
    required this.images,
    required this.currentImageIndex,
    required this.lastScrollOffset,
    required this.hasPreviousEpisode,
    required this.hasNextEpisode,
    this.hint,
  });

  final String comicId;
  final String episodeId;
  final String episodeTitle;
  final List<ComicReaderImageState> images;
  final int currentImageIndex;
  final double lastScrollOffset;
  final bool hasPreviousEpisode;
  final bool hasNextEpisode;
  final String? hint;

  ComicReaderViewState copyWith({
    List<ComicReaderImageState>? images,
    int? currentImageIndex,
    double? lastScrollOffset,
    bool? hasPreviousEpisode,
    bool? hasNextEpisode,
    String? hint,
    bool clearHint = false,
  }) {
    return ComicReaderViewState(
      comicId: comicId,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
      images: images ?? this.images,
      currentImageIndex: currentImageIndex ?? this.currentImageIndex,
      lastScrollOffset: lastScrollOffset ?? this.lastScrollOffset,
      hasPreviousEpisode: hasPreviousEpisode ?? this.hasPreviousEpisode,
      hasNextEpisode: hasNextEpisode ?? this.hasNextEpisode,
      hint: clearHint ? null : (hint ?? this.hint),
    );
  }
}

final comicReaderControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ComicReaderController, ComicReaderViewState, ComicReaderArgs>(
      (args) => ComicReaderController(args),
    );

class ComicReaderController extends AsyncNotifier<ComicReaderViewState> {
  ComicReaderController(this._args);

  final ComicReaderArgs _args;

  ComicRepository get _repository => ref.read(comicRepositoryProvider);
  ComicReaderService get _readerService => ref.read(comicReaderServiceProvider);

  @override
  FutureOr<ComicReaderViewState> build() async {
    return _loadState();
  }

  Future<void> retryImage(String imageUrl) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final idx = current.images.indexWhere((element) => element.imageUrl == imageUrl);
    if (idx < 0) {
      return;
    }

    final updatedImages = [...current.images];
    updatedImages[idx] = updatedImages[idx].copyWith(failed: false, cacheStatus: 'downloading');
    state = AsyncData(current.copyWith(images: updatedImages, clearHint: true));

    final done = await _readerService.cacheImage(imageUrl: imageUrl);
    await _repository.updateEpisodeImageCacheStatus(
      episodeId: _args.episodeId,
      imageUrl: imageUrl,
      cacheStatus: done ? 'done' : 'failed',
      cacheLocalPath: done ? imageUrl : null,
    );

    final refreshed = [...updatedImages];
    refreshed[idx] = refreshed[idx].copyWith(
      failed: !done,
      cacheStatus: done ? 'done' : 'failed',
      cacheLocalPath: done ? imageUrl : null,
    );
    state = AsyncData(
      current.copyWith(images: refreshed, hint: done ? '图片重试成功' : '图片重试失败'),
    );
  }

  Future<void> cacheCurrentEpisode() async {
    final current = state.value;
    if (current == null || current.images.isEmpty) {
      return;
    }
    for (final image in current.images) {
      await _repository.updateEpisodeImageCacheStatus(
        episodeId: _args.episodeId,
        imageUrl: image.imageUrl,
        cacheStatus: 'downloading',
      );
      final done = await _readerService.cacheImage(imageUrl: image.imageUrl);
      await _repository.updateEpisodeImageCacheStatus(
        episodeId: _args.episodeId,
        imageUrl: image.imageUrl,
        cacheStatus: done ? 'done' : 'failed',
        cacheLocalPath: done ? image.imageUrl : null,
      );
    }
    state = AsyncData((await _loadState()).copyWith(hint: '本话缓存完成'));
  }

  Future<void> cacheAllUnread() async {
    final episodes = await _repository.getComicEpisodes(comicId: _args.comicId, descending: false);
    final currentIndex = episodes.indexWhere((e) => e.episodeId == _args.episodeId);
    if (currentIndex < 0) {
      return;
    }
    final unread = episodes.skip(currentIndex).toList(growable: false);
    for (final episode in unread) {
      final images = await _ensureEpisodeImages(episode);
      for (final image in images) {
        await _repository.updateEpisodeImageCacheStatus(
          episodeId: episode.episodeId,
          imageUrl: image.imageUrl,
          cacheStatus: 'downloading',
        );
        final done = await _readerService.cacheImage(imageUrl: image.imageUrl);
        await _repository.updateEpisodeImageCacheStatus(
          episodeId: episode.episodeId,
          imageUrl: image.imageUrl,
          cacheStatus: done ? 'done' : 'failed',
          cacheLocalPath: done ? image.imageUrl : null,
        );
      }
    }
    state = AsyncData((await _loadState()).copyWith(hint: '未读章节缓存完成'));
  }

  Future<void> onScrollProgress({
    required int currentIndex,
    required double scrollOffset,
  }) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    await _repository.updateLastReadProgress(
      comicId: _args.comicId,
      episodeId: _args.episodeId,
      imageIndex: currentIndex,
      scrollOffset: scrollOffset,
    );
    state = AsyncData(
      current.copyWith(
        currentImageIndex: currentIndex,
        lastScrollOffset: scrollOffset,
      ),
    );
  }

  Future<ComicReaderViewState> _loadState() async {
    final episodes = await _repository.getComicEpisodes(comicId: _args.comicId, descending: false);
    final episodeIndex = episodes.indexWhere((e) => e.episodeId == _args.episodeId);
    if (episodeIndex < 0) {
      throw StateError('章节不存在');
    }
    final episode = episodes[episodeIndex];
    final images = await _ensureEpisodeImages(episode);
    final progress = await _repository.getLastReadProgress(comicId: _args.comicId);
    final currentImageIndex = progress != null && progress.episodeId == _args.episodeId
        ? progress.imageIndex
        : 0;
    final scrollOffset = progress != null && progress.episodeId == _args.episodeId
        ? progress.scrollOffset
        : 0.0;

    _preloadFirstBatch(images);

    return ComicReaderViewState(
      comicId: _args.comicId,
      episodeId: _args.episodeId,
      episodeTitle: episode.episodeTitle ?? '章节 ${episode.sourceTid}',
      images: images
          .map(
            (image) => ComicReaderImageState(
              imageUrl: image.imageUrl,
              imageIndex: image.imageIndex,
              cacheStatus: image.cacheStatus,
              cacheLocalPath: image.cacheLocalPath,
            ),
          )
          .toList(growable: false),
      currentImageIndex: currentImageIndex,
      lastScrollOffset: scrollOffset,
      hasPreviousEpisode: episodeIndex > 0,
      hasNextEpisode: episodeIndex < episodes.length - 1,
    );
  }

  Future<List<ComicEpisodeImageItem>> _ensureEpisodeImages(ComicEpisodeItem episode) async {
    var images = await _repository.getEpisodeImages(episodeId: episode.episodeId);
    if (images.isNotEmpty) {
      return images;
    }
    final fetched = await _readerService.fetchEpisodeImagesByTid(episode.sourceTid);
    if (fetched.isEmpty) {
      return const <ComicEpisodeImageItem>[];
    }
    await _repository.saveEpisodeImages(episodeId: episode.episodeId, imageUrls: fetched);
    images = await _repository.getEpisodeImages(episodeId: episode.episodeId);
    return images;
  }

  void _preloadFirstBatch(List<ComicEpisodeImageItem> images) {
    final limit = images.length < 3 ? images.length : 3;
    for (var i = 0; i < limit; i++) {
      final imageUrl = images[i].imageUrl;
      unawaited(_readerService.cacheImage(imageUrl: imageUrl));
    }
  }
}
