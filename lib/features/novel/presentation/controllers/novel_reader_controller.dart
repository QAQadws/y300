import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/novel_download_service.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';

class NovelReaderArgs {
  const NovelReaderArgs({
    required this.novelId,
    required this.episodeId,
  });

  final String novelId;
  final String episodeId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is NovelReaderArgs &&
        other.novelId == novelId &&
        other.episodeId == episodeId;
  }

  @override
  int get hashCode => Object.hash(novelId, episodeId);
}

class NovelReaderViewState {
  const NovelReaderViewState({
    required this.novel,
    required this.episodes,
    required this.currentEpisode,
    required this.currentContent,
    required this.document,
    required this.preferences,
    required this.currentOffset,
  });

  final NovelItem? novel;
  final List<NovelEpisodeItem> episodes;
  final NovelEpisodeItem currentEpisode;
  final NovelChapterContent currentContent;
  final NovelReaderDocument document;
  final NovelReaderPreferences preferences;
  final double currentOffset;

  NovelReaderViewState copyWith({
    NovelItem? novel,
    bool clearNovel = false,
    List<NovelEpisodeItem>? episodes,
    NovelEpisodeItem? currentEpisode,
    NovelChapterContent? currentContent,
    NovelReaderDocument? document,
    NovelReaderPreferences? preferences,
    double? currentOffset,
  }) {
    return NovelReaderViewState(
      novel: clearNovel ? null : (novel ?? this.novel),
      episodes: episodes ?? this.episodes,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      currentContent: currentContent ?? this.currentContent,
      document: document ?? this.document,
      preferences: preferences ?? this.preferences,
      currentOffset: currentOffset ?? this.currentOffset,
    );
  }
}

final novelReaderControllerProvider = AsyncNotifierProvider.autoDispose
    .family<NovelReaderController, NovelReaderViewState, NovelReaderArgs>(
  (args) => NovelReaderController(args),
);

class NovelReaderController extends AsyncNotifier<NovelReaderViewState> {
  NovelReaderController(this._args);

  final NovelReaderArgs _args;
  Timer? _saveDebounce;

  @override
  FutureOr<NovelReaderViewState> build() async {
    ref.onDispose(() => _saveDebounce?.cancel());
    return _load(_args.episodeId);
  }

  Future<void> updatePreferences(NovelReaderPreferences preferences) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    await ref.read(novelRepositoryProvider).upsertReaderPreferences(preferences);
    state = AsyncData(current.copyWith(preferences: preferences));
  }

  Future<void> openEpisode(String episodeId) async {
    final current = state.value;
    if (current == null || current.currentEpisode.episodeId == episodeId) {
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(episodeId));
  }

  Future<void> goToPreviousEpisode() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final index = current.episodes.indexWhere(
      (episode) => episode.episodeId == current.currentEpisode.episodeId,
    );
    if (index <= 0) {
      return;
    }
    await openEpisode(current.episodes[index - 1].episodeId);
  }

  Future<void> goToNextEpisode() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final index = current.episodes.indexWhere(
      (episode) => episode.episodeId == current.currentEpisode.episodeId,
    );
    if (index < 0 || index >= current.episodes.length - 1) {
      return;
    }
    await openEpisode(current.episodes[index + 1].episodeId);
  }

  Future<void> onScrollOffsetChanged(double offset) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(currentOffset: offset));

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 200), () async {
      await _saveReadingProgress(
        episodeId: current.currentEpisode.episodeId,
        offset: offset,
      );
    });
  }

  Future<void> saveCurrentOffsetNow(double offset) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    _saveDebounce?.cancel();
    state = AsyncData(current.copyWith(currentOffset: offset));
    await _saveReadingProgress(
      episodeId: current.currentEpisode.episodeId,
      offset: offset,
    );
  }

  Future<NovelReaderViewState> _load(String episodeId) async {
    final repository = ref.read(novelRepositoryProvider);
    NovelItem? novel;
    try {
      novel = await repository.getDetail(novelId: _args.novelId);
    } catch (_) {
      novel = null;
    }
    final episodes = await repository.getEpisodes(
      novelId: _args.novelId,
      descending: false,
    );
    final currentEpisode = episodes.firstWhere(
      (episode) => episode.episodeId == episodeId,
      orElse: () => episodes.first,
    );

    final downloadService = ref.read(novelDownloadServiceProvider);
    final content = await downloadService.getDownloadedChapterContent(
          novelId: _args.novelId,
          episodeId: currentEpisode.episodeId,
        ) ??
        await repository.getChapterContent(episodeId: currentEpisode.episodeId);
    if (content == null) {
      throw StateError('章节内容不存在');
    }
    final document = ref.read(novelReaderDocumentParserProvider).parse(
          episodeId: content.episodeId,
          rawHtml: content.rawHtml,
          fallbackParagraphs: content.paragraphs,
        );

    final preferences = await repository.getReaderPreferences();
    final progress = await repository.getReadingProgress(novelId: _args.novelId);
    final offset = progress != null && progress.episodeId == currentEpisode.episodeId
        ? progress.scrollOffset
        : 0.0;

    return NovelReaderViewState(
      novel: novel,
      episodes: episodes,
      currentEpisode: currentEpisode,
      currentContent: content,
      document: document,
      preferences: preferences,
      currentOffset: offset,
    );
  }

  Future<void> _saveReadingProgress({
    required String episodeId,
    required double offset,
  }) {
    return ref.read(novelRepositoryProvider).saveReadingProgress(
          novelId: _args.novelId,
          episodeId: episodeId,
          scrollOffset: offset,
        );
  }
}
