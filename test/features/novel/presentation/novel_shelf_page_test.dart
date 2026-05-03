import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/presentation/novel_shelf_page.dart';

void main() {
  testWidgets('NovelShelfPage supports fid filter and add entry', (tester) async {
    final repository = _FakeNovelRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: NovelShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-shelf-grid')), findsOneWidget);
    expect(find.text('文学区小说A'), findsOneWidget);
    expect(find.text('轻小说B'), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-filter-49')));
    await tester.pumpAndSettle();
    expect(find.text('文学区小说A'), findsOneWidget);
    expect(find.text('轻小说B'), findsNothing);

    await tester.tap(find.byKey(const Key('novel-shelf-add-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-add-fid-input')), findsOneWidget);
    expect(find.byKey(const Key('novel-add-tid-input')), findsOneWidget);
  });
}

class _FakeNovelRepository implements NovelRepository {
  final Map<String, NovelItem> _items = {
    'novel:49:100': NovelItem(
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourceFid: '49',
      title: '文学区小说A',
      author: '作者A',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 5, 3),
      episodeCount: 2,
    ),
    'novel:55:200': NovelItem(
      novelId: 'novel:55:200',
      sourceTid: '200',
      sourceFid: '55',
      title: '轻小说B',
      author: '作者B',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 5, 3),
      episodeCount: 1,
    ),
  };

  @override
  Future<NovelItem?> getDetail({required String novelId}) async => _items[novelId];

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async => null;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({required String novelId, bool descending = false}) async {
    return const <NovelEpisodeItem>[];
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async => NovelReaderPreferences.defaults();

  @override
  Future<List<NovelItem>> getShelfItems({String? sourceFid}) async {
    final all = _items.values.toList(growable: false);
    if (sourceFid == null) {
      return all;
    }
    return all.where((item) => item.sourceFid == sourceFid).toList(growable: false);
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async => null;

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId}) async {
    return const NovelEpisodeRefreshResult(insertedCount: 1, updatedCount: 0, totalCount: 1);
  }

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
  }) async {}

  @override
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {
    _items['novel:${seed.fid}:${seed.tid}'] = NovelItem(
      novelId: 'novel:${seed.fid}:${seed.tid}',
      sourceTid: seed.tid,
      sourceFid: seed.fid,
      title: '新增小说',
      author: '新增作者',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 5, 3),
      episodeCount: 1,
    );
  }

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {}
}
