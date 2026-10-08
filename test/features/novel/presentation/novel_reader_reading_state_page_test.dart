import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/repositories/library_state_repository.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/preferences/novel_chapter_interactions_dock_preferences_provider.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_spacing.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_interactions_dock_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reading_body_sliver.dart';

import '../../../test_support/localized_test_app.dart';

const _work = 'novel:49:100';
const _chapter = 'novel:49:100:5001';
const _next = 'novel:49:100:5002';
const _args = NovelReaderArgs(novelId: _work, episodeId: _chapter);

void main() {
  testWidgets('fresh short body completes only after stable real display', (
    tester,
  ) async {
    final repository = _ReadingRepository('<p>完整的短章正文。</p>');
    await tester.pumpWidget(_app(repository));
    await _pumpBodyWithoutAdvancingTime(tester);
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 249));
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(repository.completed, [_chapter]);
    expect(repository.progress[_chapter]!.progressPercent, 0);
    expect(repository.progress[_chapter]!.isProgressPercentValid, isTrue);
    expect(
      repository.progress[_chapter]!.percentBasis,
      NovelProgressPercentBasis.bodyGeometryV1,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(repository.completed, [_chapter]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'passive chapter resume preserves another chapter recent reference',
    (tester) async {
      final repository = _ReadingRepository('<p>短章历史正文。</p>');
      final saved = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 0,
        progressPercent: 0,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime(2026, 10, 1),
      );
      repository.progress[_chapter] = saved;
      repository.progress[_next] = NovelReadingProgress(
        novelId: _work,
        episodeId: _next,
        scrollOffset: 100,
        progressPercent: 0.25,
        isProgressPercentValid: true,
        updatedAt: DateTime(2026, 10, 2),
      );
      repository.recent = _next;
      await tester.pumpWidget(_app(repository));
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(repository.completed, isEmpty);
      expect(repository.committed, isEmpty);
      expect(repository.recent, _next);
      expect(repository.progress[_chapter], same(saved));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.recent, _next);
      expect(repository.progress[_chapter], same(saved));
    },
  );

  testWidgets('actual body percentage excludes chrome padding and transition', (
    tester,
  ) async {
    final repository = _ReadingRepository(
      '<div style="height: 1600px">长章正文。</div>',
    );
    await tester.pumpWidget(_app(repository));
    await _pumpBodyWithoutAdvancingTime(tester);
    await tester.drag(
      find.byKey(const Key('novel-reader-paragraph-list')),
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    final bodyFinder = find.byType(NovelReadingBodySliver);
    final body = tester.renderObject<RenderSliver>(bodyFinder);
    final padding =
        tester
                .widget<SliverPadding>(
                  find.byKey(const Key('novel-reader-content-column')),
                )
                .padding
            as EdgeInsets;
    final position = _verticalPosition(tester);
    final topChrome = padding.top - NovelReaderSpacing.verticalPagePadding;
    final bottomChrome =
        padding.bottom - NovelReaderSpacing.verticalPagePadding;
    final range =
        body.geometry!.scrollExtent -
        (position.viewportDimension - topChrome - bottomChrome);
    final expected =
        ((position.pixels +
                    topChrome -
                    body.constraints.precedingScrollExtent) /
                range)
            .clamp(0.0, 1.0);
    final snapshot = _state(tester).progressSnapshot;
    expect(snapshot.progressPercent, closeTo(expected, 0.005));
    expect(snapshot.percentBasis, NovelProgressPercentBasis.bodyGeometryV1);
    expect(position.maxScrollExtent, greaterThan(range));
    expect(repository.completed, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending image first frame cannot complete a short chapter', (
    tester,
  ) async {
    final repository = _ReadingRepository(
      '<p>图文短章。</p><img src="https://images.test/pending.png" width="100" height="100">',
    );
    final images = _PendingImageCache();
    await tester.pumpWidget(_app(repository, images: images));
    await _pumpBodyWithoutAdvancingTime(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(images.requests, isNotEmpty);
    expect(repository.completed, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'body percentage resumes at the same offset through safe area without rewriting history',
    (tester) async {
      const safeArea = EdgeInsets.only(top: 24, bottom: 18);
      final repository = _ReadingRepository(
        '<div style="height: 1600px">具有安全区的往返阅读正文。</div>',
      );
      await tester.pumpWidget(_app(repository, safeArea: safeArea));
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final sourcePosition = _verticalPosition(tester);
      final originalOffset = sourcePosition.pixels;
      final geometry = _bodyLayout(tester);
      expect(geometry.topChrome, greaterThanOrEqualTo(safeArea.top));
      expect(geometry.bottomChrome, greaterThanOrEqualTo(safeArea.bottom));
      final saved = repository.progress[_chapter]!;
      expect(saved.progressPercent, greaterThan(0));
      expect(saved.progressPercent, lessThan(1));
      expect(saved.isProgressPercentValid, isTrue);
      expect(saved.percentBasis, NovelProgressPercentBasis.bodyGeometryV1);
      expect(saved.scrollOffset, closeTo(originalOffset, 0.5));
      expect(repository.completed, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter], same(saved));
      final originalCommitCount = repository.committed.length;
      await tester.pumpWidget(_app(repository, safeArea: safeArea));
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_verticalPosition(tester).pixels, closeTo(originalOffset, 1));
      expect(
        _state(tester).progressSnapshot.progressPercent,
        closeTo(saved.progressPercent, 0.005),
      );
      expect(repository.progress[_chapter], same(saved));
      expect(repository.progress[_chapter]!.updatedAt, saved.updatedAt);
      expect(repository.committed, hasLength(originalCommitCount));
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter], same(saved));
    },
  );

  testWidgets(
    'paged body percentage restores vertical content without the transition range',
    (tester) async {
      final repository = _ReadingRepository(
        '<div style="height: 1600px">从横向阅读恢复的正文。</div>',
      );
      final saved = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        flowMode: NovelReaderFlowMode.pagedLtr,
        scrollOffset: 0,
        pageIndex: 2,
        pageCount: 5,
        paginationKey: 'previous-paged-layout',
        progressPercent: 0.4,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.pagedStartV1,
        updatedAt: DateTime(2026, 10, 1),
      );
      repository.progress[_chapter] = saved;
      repository.recent = _chapter;
      await tester.pumpWidget(
        _app(repository, safeArea: const EdgeInsets.only(top: 24, bottom: 18)),
      );
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final position = _verticalPosition(tester);
      final geometry = _bodyLayout(tester);
      final expected =
          geometry.bodyTop +
          saved.progressPercent * geometry.bodyRange -
          geometry.topChrome;
      expect(position.pixels, closeTo(expected, 1));
      expect(position.maxScrollExtent, greaterThan(geometry.bodyRange));
      expect(
        (position.pixels - saved.progressPercent * position.maxScrollExtent)
            .abs(),
        greaterThan(5),
      );
      expect(repository.committed, isEmpty);
      expect(repository.completed, isEmpty);
      expect(repository.progress[_chapter], same(saved));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter], same(saved));
    },
  );

  testWidgets('covering the reader cancels pending short body completion', (
    tester,
  ) async {
    final repository = _ReadingRepository('<p>暂时被覆盖的短章。</p>');
    final navigation = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(repository, navigation: navigation));
    await _pumpBodyWithoutAdvancingTime(tester);
    unawaited(
      navigation.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('覆盖页面'))),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.completed, isEmpty);
    navigation.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.completed, [_chapter]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (hiddenByRoute, shortBody) in [
    (true, false),
    (false, false),
    (true, true),
  ]) {
    testWidgets(
      'first ${shortBody ? 'short' : 'long'} body display while ${hiddenByRoute ? 'covered' : 'paused'} records history only after returning visible',
      (tester) async {
        final repository = _ReadingRepository(
          shortBody
              ? '<p>延迟准备完成的完整短章。</p>'
              : '<div style="height: 1600px">延迟准备完成的正文。</div>',
        );
        final preparation = _GatedHtmlPreparation();
        final navigation = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          _app(repository, navigation: navigation, preparation: preparation),
        );
        for (var frame = 0; frame < 200 && !preparation.started; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump();
        }
        expect(preparation.started, isTrue);
        expect(repository.committed, isEmpty);
        if (hiddenByRoute) {
          unawaited(
            navigation.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('覆盖页面')),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
        }

        preparation.gate.complete();
        if (hiddenByRoute) {
          await _pumpBodyWithoutAdvancingTime(tester, skipOffstage: false);
        } else {
          // Paused Flutter suppresses frame builds even though the underlying
          // preparation future can finish on the Dart event loop.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pump(const Duration(seconds: 1));
        expect(repository.progress, isEmpty);
        expect(repository.committed, isEmpty);
        expect(repository.completed, isEmpty);
        expect(repository.recent, isNull);

        if (hiddenByRoute) {
          navigation.currentState!.pop();
          await tester.pumpAndSettle();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
        }
        await _pumpBodyWithoutAdvancingTime(tester);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(
          ModalRoute.of(
            tester.element(find.byType(NovelReaderPage)),
          )!.isCurrent,
          isTrue,
        );
        expect(
          _state(tester).progressSnapshot.percentBasis,
          NovelProgressPercentBasis.bodyGeometryV1,
        );
        expect(repository.committed, hasLength(shortBody ? 2 : 1));
        expect(repository.recent, _chapter);
        expect(
          repository.progress[_chapter]!.percentBasis,
          NovelProgressPercentBasis.bodyGeometryV1,
        );
        if (shortBody) {
          // A fresh first position and confirmed completion both survive the
          // same geometry publication; neither must retire the other's lease.
          expect(repository.commitCompletionFlags, [false, true]);
          expect(repository.completed, [_chapter]);
          expect(repository.progress[_chapter]!.progressPercent, 0);
        } else {
          expect(repository.commitCompletionFlags, [false]);
          expect(repository.completed, isEmpty);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('app background cancels pending completion until resumed', (
    tester,
  ) async {
    final repository = _ReadingRepository('<p>进入后台前的短章。</p>');
    await tester.pumpWidget(_app(repository));
    await _pumpBodyWithoutAdvancingTime(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(repository.completed, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.completed, [_chapter]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('real reading navigation confirms the actual long body tail', (
    tester,
  ) async {
    final repository = _ReadingRepository(
      '<div style="height: 1600px">长章的实际正文。</div>',
    );
    await tester.pumpWidget(_app(repository));
    await _pumpBodyWithoutAdvancingTime(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.completed, isEmpty);
    await tester.drag(
      find.byKey(const Key('novel-reader-paragraph-list')),
      const Offset(0, -1450),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.completed, [_chapter]);
    expect(repository.progress[_chapter]!.progressPercent, 1);
    expect(repository.recent, _chapter);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pumpBodyWithoutAdvancingTime(
  WidgetTester tester, {
  bool skipOffstage = true,
}) async {
  for (var frame = 0; frame < 200; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump();
    if (find
            .byType(ForumHtmlWidgetPostRenderer, skipOffstage: skipOffstage)
            .evaluate()
            .isNotEmpty &&
        find
            .byKey(
              const Key('novel-reader-delayed-loading-surface'),
              skipOffstage: skipOffstage,
            )
            .evaluate()
            .isEmpty) {
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return;
    }
  }
  expect(
    find.byType(ForumHtmlWidgetPostRenderer, skipOffstage: skipOffstage),
    findsWidgets,
  );
}

NovelReaderViewState _state(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(NovelReaderPage)),
  listen: false,
).read(novelReaderControllerProvider(_args)).value!;

ScrollPosition _verticalPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('novel-reader-paragraph-list')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

({double bodyTop, double bodyRange, double topChrome, double bottomChrome})
_bodyLayout(WidgetTester tester) {
  final body = tester.renderObject<RenderSliver>(
    find.byType(NovelReadingBodySliver),
  );
  final padding =
      tester
              .widget<SliverPadding>(
                find.byKey(const Key('novel-reader-content-column')),
              )
              .padding
          as EdgeInsets;
  final topChrome = padding.top - NovelReaderSpacing.verticalPagePadding;
  final bottomChrome = padding.bottom - NovelReaderSpacing.verticalPagePadding;
  return (
    bodyTop: body.constraints.precedingScrollExtent,
    bodyRange:
        body.geometry!.scrollExtent -
        (_verticalPosition(tester).viewportDimension -
            topChrome -
            bottomChrome),
    topChrome: topChrome,
    bottomChrome: bottomChrome,
  );
}

Widget _app(
  _ReadingRepository repository, {
  GlobalKey<NavigatorState>? navigation,
  _PendingImageCache? images,
  NovelReaderHtmlPreparationService? preparation,
  EdgeInsets safeArea = EdgeInsets.zero,
}) => ProviderScope(
  overrides: [
    novelRepositoryProvider.overrideWithValue(repository),
    novelReaderPreferencesRepositoryProvider.overrideWithValue(
      _ReadingPreferences(),
    ),
    novelChapterInteractionsDockPreferencesRepositoryProvider.overrideWithValue(
      _DisabledDock(),
    ),
    libraryStateRepositoryProvider.overrideWithValue(_UnusedLibraryState()),
    forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
    imageCacheServiceProvider.overrideWithValue(images ?? _PendingImageCache()),
    if (preparation != null)
      novelReaderHtmlPreparationServiceProvider.overrideWithValue(preparation),
  ],
  child: LocalizedTestApp(
    navigatorKey: navigation,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(padding: safeArea, viewPadding: safeArea),
      child: child!,
    ),
    home: const NovelReaderPage(novelId: _work, initialEpisodeId: _chapter),
  ),
);

class _GatedHtmlPreparation implements NovelReaderHtmlPreparationService {
  final gate = Completer<void>();
  bool started = false;
  static const _delegate = DefaultNovelReaderHtmlPreparationService();

  @override
  int get legacyMarkupNormalizerRevision =>
      _delegate.legacyMarkupNormalizerRevision;

  @override
  Future<NovelReaderPreparedChapter> prepare({
    required String rawHtml,
    required NovelEpisodeItem episode,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
    NovelReaderDocument? semanticDocument,
  }) async {
    started = true;
    await gate.future;
    return _delegate.prepare(
      rawHtml: rawHtml,
      episode: episode,
      preferences: preferences,
      theme: theme,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
      semanticDocument: semanticDocument,
    );
  }
}

class _ReadingRepository
    implements NovelRepository, NovelReadingStateRepository {
  _ReadingRepository(this.html);
  final String html;
  final progress = <String, NovelReadingProgress>{};
  final states = <String, LibraryEpisodeState>{};
  final committed = <NovelReadingProgress>[];
  final commitCompletionFlags = <bool>[];
  final completed = <String>[];
  String? recent;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async => [
    const NovelEpisodeItem(
      episodeId: _chapter,
      novelId: _work,
      sourceTid: '100',
      sourcePid: '5001',
      episodeTitle: '第一章',
      orderIndex: 0,
    ),
    const NovelEpisodeItem(
      episodeId: _next,
      novelId: _work,
      sourceTid: '100',
      sourcePid: '5002',
      episodeTitle: '下一章',
      orderIndex: 1,
    ),
  ];
  @override
  Future<NovelChapterContent?> getChapterContent({
    required String episodeId,
  }) async => NovelChapterContent(
    episodeId: episodeId,
    rawHtml: html,
    plainText: '正文',
    paragraphs: const ['正文'],
  );
  @override
  Future<NovelItem?> getDetail({required String novelId}) async => NovelItem(
    novelId: novelId,
    sourceTid: '100',
    sourceFid: '49',
    title: '测试作品',
    updatedAt: DateTime(2026, 10, 1),
    episodeCount: 2,
  );
  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async => [];
  @override
  Future<NovelReadingStateSnapshot> loadWorkState({
    required String novelId,
  }) async => NovelReadingStateSnapshot(
    novelId: novelId,
    progressByEpisode: progress,
    episodeStates: states,
    recentEpisodeId: recent,
  );
  @override
  Future<NovelReadingProgress?> getChapterProgress({
    required String novelId,
    required String episodeId,
  }) async => progress[episodeId];
  @override
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  }) async {
    if (canCommit?.call() == false) return false;
    this.progress[progress.episodeId] = progress;
    recent = progress.episodeId;
    committed.add(progress);
    commitCompletionFlags.add(markCompleted);
    if (markCompleted && states[progress.episodeId]?.isRead != true) {
      completed.add(progress.episodeId);
      states[progress.episodeId] = LibraryEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: progress.episodeId,
        workId: _work,
        isRead: true,
      );
    }
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository call: ${invocation.memberName}');
}

class _ReadingPreferences implements NovelReaderPreferencesRepository {
  NovelReaderPreferences preferences = NovelReaderPreferences.defaults()
      .copyWith(flowMode: NovelReaderFlowMode.vertical);
  @override
  Future<NovelReaderPreferences> load() async => preferences;
  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    this.preferences = preferences;
  }
}

class _DisabledDock
    implements NovelChapterInteractionsDockPreferencesRepository {
  @override
  Future<NovelChapterInteractionsDockPreferences> load() async =>
      const NovelChapterInteractionsDockPreferences(enabled: false);
  @override
  Future<void> save(
    NovelChapterInteractionsDockPreferences preferences,
  ) async {}
}

class _UnusedLibraryState implements LibraryStateRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected shared-state call: ${invocation.memberName}',
  );
}

class _PendingImageCache implements ImageCacheService {
  final requests = <ImageCacheRequest>[];
  final pending = Completer<CachedImageResult>();
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) {
    requests.add(request);
    return pending.future;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected image-cache call: ${invocation.memberName}');
}
