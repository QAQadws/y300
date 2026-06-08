import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_download_service.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

void main() {
  test('NovelReaderViewState derives episode boundaries', () {
    final episodes = _episodes();

    final first = _viewState(episodes: episodes, currentEpisode: episodes.first);
    expect(first.currentEpisodeIndex, 0);
    expect(first.previousEpisode, isNull);
    expect(first.nextEpisode?.episodeId, episodes[1].episodeId);
    expect(first.hasPreviousEpisode, isFalse);
    expect(first.hasNextEpisode, isTrue);

    final middle = _viewState(episodes: episodes, currentEpisode: episodes[1]);
    expect(middle.currentEpisodeIndex, 1);
    expect(middle.previousEpisode?.episodeId, episodes.first.episodeId);
    expect(middle.nextEpisode?.episodeId, episodes.last.episodeId);
    expect(middle.hasPreviousEpisode, isTrue);
    expect(middle.hasNextEpisode, isTrue);

    final last = _viewState(episodes: episodes, currentEpisode: episodes.last);
    expect(last.currentEpisodeIndex, 2);
    expect(last.previousEpisode?.episodeId, episodes[1].episodeId);
    expect(last.nextEpisode, isNull);
    expect(last.hasPreviousEpisode, isTrue);
    expect(last.hasNextEpisode, isFalse);
  });

  test('NovelReaderController loads readingProgress into state', () async {
    final progress = NovelReadingProgress(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5002',
      scrollOffset: 88,
      updatedAt: DateTime(2026, 6, 1),
    );
    final repository = _ControllerNovelRepository(readingProgress: progress);
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5002',
    );
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final state = await container.read(
      novelReaderControllerProvider(args).future,
    );

    expect(state.readingProgress?.episodeId, 'novel:49:100:5002');
    expect(state.currentOffset, 88);
  });

  test('openEpisodeFromCatalog loads target and preserves target progress', () async {
    final targetProgress = NovelReadingProgress(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5002',
      scrollOffset: 88,
      updatedAt: DateTime(2026, 6, 1),
    );
    final repository = _ControllerNovelRepository(
      readingProgress: targetProgress,
    );
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final initial = await container.read(provider.future);
    expect(initial.currentEpisode.episodeId, 'novel:49:100:5001');
    expect(initial.currentOffset, 0);

    final controller = container.read(provider.notifier);
    await controller.saveCurrentOffsetNow(12);
    await controller.openEpisodeFromCatalog('novel:49:100:5002');

    final state = await container.read(provider.future);
    expect(state.currentEpisode.episodeId, 'novel:49:100:5002');
    expect(state.currentOffset, 88);
    expect(repository.savedProgressEpisodeIds, contains('novel:49:100:5001'));
  });
}

ProviderSubscription<AsyncValue<NovelReaderViewState>> _keepReaderAlive(
  ProviderContainer container,
  NovelReaderArgs args,
) {
  return container.listen<AsyncValue<NovelReaderViewState>>(
    novelReaderControllerProvider(args),
    (_, _) {},
  );
}

ProviderContainer _buildContainer({
  required _ControllerNovelRepository repository,
}) {
  return ProviderContainer(
    overrides: [
      novelRepositoryProvider.overrideWithValue(repository),
      novelDownloadServiceProvider.overrideWithValue(_NoopNovelDownloadService()),
    ],
  );
}

NovelReaderViewState _viewState({
  required List<NovelEpisodeItem> episodes,
  required NovelEpisodeItem currentEpisode,
}) {
  return NovelReaderViewState(
    novel: null,
    episodes: episodes,
    currentEpisode: currentEpisode,
    currentContent: _content(currentEpisode.episodeId, '正文。'),
    document: _document(currentEpisode.episodeId),
    preferences: NovelReaderPreferences.defaults(),
    readingProgress: null,
    currentOffset: 0,
  );
}

class _NoopNovelDownloadService implements NovelDownloadService {
  @override
  Future<void> deleteChapterDownload({
    required String novelId,
    required String episodeId,
  }) async {}

  @override
  Future<DownloadedNovelChapter> downloadChapter({
    required String novelId,
    required String episodeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelChapterContent?> getDownloadedChapterContent({
    required String novelId,
    required String episodeId,
  }) async {
    return null;
  }
}

class _ControllerNovelRepository implements NovelRepository {
  _ControllerNovelRepository({
    this.readingProgress,
  }) {
    contentsByEpisodeId = <String, NovelChapterContent>{
      for (final episode in episodes)
        episode.episodeId: _content(episode.episodeId, '${episode.episodeTitle}正文。'),
    };
  }

  final episodes = _episodes();
  late final Map<String, NovelChapterContent> contentsByEpisodeId;
  NovelReadingProgress? readingProgress;
  final savedProgressEpisodeIds = <String>[];

  @override
  Future<String> createCategory({required String name}) async => 'default';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return const <NovelShelfCategory>[];
  }

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async {
    return contentsByEpisodeId[episodeId];
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '49',
      title: '测试小说',
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: episodes.length,
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return descending ? episodes.reversed.toList(growable: false) : episodes;
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async {
    return NovelReaderPreferences.defaults();
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async {
    return readingProgress;
  }

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async {
    return const <NovelItem>[];
  }

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
  }) async {
    return NovelEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: episodes.length,
    );
  }

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
  }) async {
    savedProgressEpisodeIds.add(episodeId);
    readingProgress = NovelReadingProgress(
      novelId: novelId,
      episodeId: episodeId,
      scrollOffset: scrollOffset,
      updatedAt: DateTime(2026, 6, 8),
    );
  }

  @override
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {}

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {}
}

List<NovelEpisodeItem> _episodes() {
  return const <NovelEpisodeItem>[
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5001',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5001',
      sourcePage: 1,
      episodeTitle: '第1章',
      orderIndex: 0,
      datelineText: '2026-05-03',
    ),
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5002',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5002',
      sourcePage: 1,
      episodeTitle: '第2章',
      orderIndex: 1,
      datelineText: '2026-05-04',
    ),
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5003',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5003',
      sourcePage: 1,
      episodeTitle: '第3章',
      orderIndex: 2,
      datelineText: '2026-05-05',
    ),
  ];
}

NovelChapterContent _content(String episodeId, String text) {
  return NovelChapterContent(
    episodeId: episodeId,
    rawHtml: '<p>$text</p>',
    plainText: text,
    paragraphs: <String>[text],
  );
}

NovelReaderDocument _document(String episodeId) {
  return NovelReaderDocument(
    episodeId: episodeId,
    rawHtmlHash: 'test',
    nodes: <NovelReaderNode>[
      NovelReaderNode(
        id: 'node-0',
        type: NovelReaderNodeType.paragraph,
        text: '正文。',
      ),
    ],
    plainText: '正文。',
    wordCount: 3,
  );
}
