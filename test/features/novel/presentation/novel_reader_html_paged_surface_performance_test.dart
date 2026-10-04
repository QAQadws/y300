import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_anchor_navigation_request.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_diagnostics.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_forum_html_render_theme_factory.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_session_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_prepared_chapter_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_coordinator.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  testWidgets('remounting the paged surface hits the reader session plan', (
    tester,
  ) async {
    final owner = NovelReaderPaginationSessionCache();
    final diagnostics = _RecordingDiagnosticsSink();
    final host =
        _BudgetSurfaceHost(
            _BudgetPaginationCoordinator(),
            enforceBudgets: false,
          )
          ..useDefaultCoordinator = true
          ..paginationCache = owner.paginationCache
          ..measureCache = owner.measureCache
          ..boundaryCache = owner.boundaryCache
          ..preparedCache = owner.preparedChapterCache
          ..diagnosticsSink = diagnostics;
    addTearDown(owner.dispose);
    await tester.pumpWidget(host.build());
    for (
      var frame = 0;
      frame < 120 && owner.paginationCache.length == 0;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    final cold = diagnostics.records.lastWhere((entry) => entry.isComplete);
    expect(cold.cacheHit, isFalse);
    expect(
      owner.paginationCache.length,
      1,
      reason: 'closed=${owner.isClosed}, ${diagnostics.records}',
    );
    expect(owner.preparedChapterCache.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(owner.isClosed, isFalse);
    diagnostics.records.clear();
    await tester.pumpWidget(host.build());
    await tester.pumpAndSettle();
    final warm = diagnostics.records.lastWhere((entry) => entry.isComplete);
    expect(warm.cacheHit, isTrue);
    expect(warm.paginationKey, cold.paginationKey);
    expect(warm.pageCount, cold.pageCount);
    expect(
      find.byKey(const Key('novel-reader-paged-page-view')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final cacheKind in ['plan', 'measure', 'boundary']) {
    testWidgets('same layout rebinds a replaced $cacheKind cache', (
      tester,
    ) async {
      final coordinator = _BudgetPaginationCoordinator();
      final host = _BudgetSurfaceHost(coordinator, enforceBudgets: false);
      _disposeBudgetHost(tester, coordinator);
      await _pumpBudgetHost(tester, host);
      coordinator.emit(0, pageCount: 3, isComplete: true);
      await tester.pump();
      await tester.pump();
      final originalKey = coordinator.attempts.single.key;
      final originalCache = NovelReaderPaginationCache();
      final originalMeasureCache = NovelReaderPaginationMeasureCache();
      final originalBoundaryCache = NovelReaderComplexHtmlBoundaryCache();
      switch (cacheKind) {
        case 'plan':
          host.paginationCache = originalCache;
        case 'measure':
          host.measureCache = originalMeasureCache;
        case 'boundary':
          host.boundaryCache = originalBoundaryCache;
      }
      await tester.pumpWidget(host.build());
      await tester.pump();
      await tester.pump();
      expect(coordinator.attempts, hasLength(2));
      expect(coordinator.attempts.last.key, originalKey);
      expect(coordinator.cancelPendingCount, greaterThan(0));
      coordinator.emit(0, pageCount: 3, isComplete: true);
      coordinator.fail(0);
      coordinator.emit(1, pageCount: 3, isComplete: true);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('novel-reader-pagination-failure')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(originalCache.isClosed, isFalse);
      expect(originalMeasureCache.isClosed, isFalse);
      expect(originalBoundaryCache.isClosed, isFalse);
      expect(tester.takeException(), isNull);
      originalCache.dispose();
      originalMeasureCache.dispose();
      originalBoundaryCache.dispose();
    });
  }

  testWidgets(
    'same HTML hash rechecks changed semantic conversion provenance',
    (tester) async {
      final coordinator = _BudgetPaginationCoordinator();
      final preparation = _GatedPreparationService();
      final host = _BudgetSurfaceHost(
        coordinator,
        preparationService: preparation,
        enforceBudgets: false,
      );
      _disposeBudgetHost(tester, coordinator);
      NovelReaderDocument document(String identity) => NovelReaderDocument(
        episodeId: _episode.episodeId,
        rawHtmlHash: 'same-raw-hash',
        body: RichDocument.empty,
        plainText: '',
        wordCount: 0,
        textConversionIdentity: identity,
      );
      host.semanticDocument = document('original');
      await _pumpBudgetHost(tester, host);
      host.semanticDocument = document('simplified');
      await tester.pumpWidget(host.build());
      await tester.pump();
      expect(preparation.requests, hasLength(2));
      expect(
        preparation.semanticDocuments.map((doc) => doc?.textConversionIdentity),
        ['original', 'simplified'],
      );
      final chapter = await const DefaultNovelReaderHtmlPreparationService()
          .prepare(
            rawHtml: _budgetRawHtml,
            episode: _episode,
            preferences: const NovelHtmlReaderPreferencesAdapter().map(
              host.preferences,
            ),
            theme: host.htmlTheme,
            sourceId: _episode.episodeId,
            threadId: _episode.sourceTid,
            imageCacheOwnerId: _episode.sourceTid,
          );
      preparation.requests.first.complete(chapter);
      await tester.pump();
      expect(coordinator.attempts, isEmpty);
      preparation.requests.last.complete(chapter);
      await tester.pump();
      await tester.pump();
      expect(coordinator.attempts, hasLength(1));
    },
  );

  testWidgets('paged surface uses safe insets in its pagination geometry', (
    tester,
  ) async {
    final preferences = NovelReaderPreferences.defaults().copyWith(
      flowMode: NovelReaderFlowMode.pagedLtr,
    );
    final theme = ThemeData.light();
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: preferences,
      theme: theme,
    );
    final htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(
      palette,
    );
    final coordinator = _CompleteRecordingPaginationCoordinator();

    Widget buildSurface(ReaderChromeInsets insets) {
      return LocalizedTestApp(
        theme: theme,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(top: 24, bottom: 30),
            ),
            child: NovelReaderHtmlPagedSurface(
              rawHtml: '<p>安全区分页几何</p>',
              episode: _episode,
              preferences: preferences,
              typography: const NovelReaderTypographyResolver().resolve(
                preferences: preferences,
                theme: theme,
                palette: palette,
              ),
              theme: htmlTheme,
              imageReferer: 'https://bbs.yamibo.com/',
              progressSnapshot: const NovelReaderProgressSnapshot(
                novelId: 'performance-novel',
                episodeId: 'performance-episode',
                flowMode: NovelReaderFlowMode.pagedLtr,
                scrollOffset: 0,
                pageIndex: 0,
                progressPercent: 0,
              ),
              chromeInsets: insets,
              coordinatorBuilder:
                  ({
                    required BuildContext context,
                    required ForumHtmlThemeContext theme,
                    required ForumHtmlReaderPreferences preferences,
                    required String sourceId,
                    required String? threadId,
                    required String? imageCacheOwnerId,
                    required String? imageReferer,
                  }) => coordinator,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      buildSurface(
        const ReaderChromeInsets(safeAreaTop: 24, safeAreaBottom: 30),
      ),
    );
    await tester.pumpAndSettle();
    final safeKey = coordinator.lastKey;

    await tester.pumpWidget(buildSurface(const ReaderChromeInsets.zero()));
    await tester.pumpAndSettle();
    final normalKey = coordinator.lastKey;

    expect(safeKey, isNotNull);
    expect(normalKey, isNotNull);
    expect(safeKey!.topChromeInsetPx, 24);
    expect(safeKey.bottomChromeInsetPx, 30);
    expect(normalKey!.topChromeInsetPx, 0);
    expect(normalKey.bottomChromeInsetPx, 0);
    expect(safeKey.viewportHeightPx, lessThan(normalKey.viewportHeightPx));
  });

  testWidgets('paged surface clips inline media on the first page frame', (
    tester,
  ) async {
    final preferences = NovelReaderPreferences.defaults().copyWith(
      flowMode: NovelReaderFlowMode.pagedLtr,
    );
    final theme = ThemeData.light();
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: preferences,
      theme: theme,
    );
    final htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(
      palette,
    );
    final typography = const NovelReaderTypographyResolver().resolve(
      preferences: preferences,
      theme: theme,
      palette: palette,
    );
    final coordinator = _CompleteRecordingPaginationCoordinator(
      pageHtml:
          '<p><img src="data/attachment/forum/chapter-image.jpg" '
          'width="640" height="480"></p>'
          '<img src="static/image/smiley/gexing/008.gif" '
          'width="24" height="24">',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
        ],
        child: LocalizedTestApp(
          theme: theme,
          home: Scaffold(
            body: NovelReaderHtmlPagedSurface(
              rawHtml: coordinator.pageHtml,
              episode: _episode,
              preferences: preferences,
              typography: typography,
              theme: htmlTheme,
              imageReferer: 'https://bbs.yamibo.com/',
              progressSnapshot: const NovelReaderProgressSnapshot(
                novelId: 'performance-novel',
                episodeId: 'performance-episode',
                flowMode: NovelReaderFlowMode.pagedLtr,
                scrollOffset: 0,
                pageIndex: 0,
                progressPercent: 0,
              ),
              coordinatorBuilder:
                  ({
                    required BuildContext context,
                    required ForumHtmlThemeContext theme,
                    required ForumHtmlReaderPreferences preferences,
                    required String sourceId,
                    required String? threadId,
                    required String? imageCacheOwnerId,
                    required String? imageReferer,
                  }) => coordinator,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final images = find.byType(CachedLibraryImage);
    expect(images, findsNWidgets(2));
    for (var index = 0; index < 2; index += 1) {
      final clip = tester.widget<ClipRRect>(
        find
            .ancestor(of: images.at(index), matching: find.byType(ClipRRect))
            .first,
      );
      expect(clip.borderRadius, const BorderRadius.all(Radius.circular(4)));
    }
  });

  testWidgets('target timeout is recoverable and retry rejects old results', (
    tester,
  ) async {
    final coordinator = _BudgetPaginationCoordinator();
    final host = _BudgetSurfaceHost(coordinator);
    _disposeBudgetHost(tester, coordinator);
    await _pumpBudgetHost(tester, host);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(
      find.byKey(const Key('novel-reader-pagination-failure')),
      findsOneWidget,
    );
    expect(host.scrollChoices, 0);
    expect(coordinator.cancelPendingCount, 1);
    expect(host.positions, isEmpty);
    await tester.tap(find.byKey(const Key('novel-reader-pagination-retry')));
    await tester.pump();
    await tester.pump();
    expect(coordinator.attempts, hasLength(2));
    expect(
      find.byKey(const Key('novel-reader-pagination-failure')),
      findsNothing,
    );
    coordinator.emit(0, pageCount: 3, isComplete: true);
    coordinator.fail(0);
    await tester.pump();
    expect(host.positions, isEmpty);
    coordinator.emit(1, pageCount: 3, isComplete: true);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('novel-reader-paged-page-view')),
      findsOneWidget,
    );
    expect(host.positions.last.pageIndex, 0);
    expect(host.scrollChoices, 0);
    expect(coordinator.clearCount, 0);
    final reports = host.positions.length;
    await tester.pumpWidget(const SizedBox.shrink());
    coordinator.emit(1, pageCount: 3, isComplete: true);
    coordinator.fail(1);
    await tester.pump();
    expect(host.positions, hasLength(reports));
    expect(host.scrollChoices, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the explicit scroll button requests another mode', (
    tester,
  ) async {
    final coordinator = _BudgetPaginationCoordinator();
    final host = _BudgetSurfaceHost(coordinator);
    _disposeBudgetHost(tester, coordinator);
    await _pumpBudgetHost(tester, host);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(host.scrollChoices, 0);
    await tester.tap(find.byKey(const Key('novel-reader-pagination-fallback')));
    await tester.pump();
    expect(host.scrollChoices, 1);
  });

  testWidgets('preparation retry does not consume a late retired result', (
    tester,
  ) async {
    final coordinator = _BudgetPaginationCoordinator();
    final preparation = _GatedPreparationService();
    final host = _BudgetSurfaceHost(
      coordinator,
      preparationService: preparation,
    );
    final chapter = await const DefaultNovelReaderHtmlPreparationService()
        .prepare(
          rawHtml: _budgetRawHtml,
          episode: _episode,
          preferences: const NovelHtmlReaderPreferencesAdapter().map(
            host.preferences,
          ),
          theme: host.htmlTheme,
          sourceId: _episode.episodeId,
          threadId: _episode.sourceTid,
          imageCacheOwnerId: _episode.sourceTid,
        );
    _disposeBudgetHost(tester, coordinator);
    await _pumpBudgetHost(tester, host);
    expect(preparation.requests, hasLength(1));
    expect(coordinator.attempts, isEmpty);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(
      find.byKey(const Key('novel-reader-pagination-failure')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('novel-reader-pagination-retry')));
    await tester.pump();
    expect(preparation.requests, hasLength(2));

    preparation.requests.first.complete(chapter);
    await tester.pump();
    await tester.pump();
    expect(coordinator.attempts, isEmpty);
    expect(host.positions, isEmpty);
    expect(
      find.byKey(const Key('novel-reader-paged-preparing')),
      findsOneWidget,
    );
    preparation.requests.last.complete(chapter);
    await tester.pump();
    await tester.pump();
    expect(coordinator.attempts, hasLength(1));
    coordinator.emit(0, pageCount: 3, isComplete: true);
    await tester.pump();
    await tester.pump();
    expect(host.positions.last.pageIndex, 0);
    expect(host.scrollChoices, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an uncovered restore target times out despite earlier page events',
    (tester) async {
      final coordinator = _BudgetPaginationCoordinator();
      final host = _BudgetSurfaceHost(
        coordinator,
        targetPageWait: const Duration(milliseconds: 50),
      );
      host.snapshot = host.snapshot.copyWith(
        pageIndex: 99,
        paginationKey: 'previous-layout',
        anchorNodeId: 'paragraph-2',
        anchorFormatVersion: 1,
        anchorTextIdentity: NovelReaderAnchorFormat.textIdentity('尾页'),
        isProgressPercentValid: false,
      );
      _disposeBudgetHost(tester, coordinator);
      await _pumpBudgetHost(tester, host);
      coordinator.emit(0, pageCount: 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      coordinator.emit(0, pageCount: 2);
      await tester.pump();
      expect(
        find.byKey(const Key('novel-reader-paged-restoring-position')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump();
      expect(
        find.byKey(const Key('novel-reader-pagination-failure')),
        findsOneWidget,
      );
      expect(host.positions, isEmpty);
      expect(host.scrollChoices, 0);
      await tester.tap(find.byKey(const Key('novel-reader-pagination-retry')));
      await tester.pump();
      coordinator.emit(1, pageCount: 3, isComplete: true);
      await tester.pump();
      await tester.pump();
      expect(host.positions.last.pageIndex, 2);
      expect(host.positions.last.isReadOnlyCompatibilityRestore, isFalse);
    },
  );

  testWidgets('a changed navigation request receives its own waiting budget', (
    tester,
  ) async {
    final coordinator = _BudgetPaginationCoordinator();
    final host = _BudgetSurfaceHost(coordinator);
    host.navigationRequest = _budgetNavigation(1, 1);
    _disposeBudgetHost(tester, coordinator);
    await _pumpBudgetHost(tester, host);
    await tester.pump(const Duration(milliseconds: 30));
    host.navigationRequest = _budgetNavigation(2, 2);
    await tester.pumpWidget(host.build());
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      find.byKey(const Key('novel-reader-pagination-failure')),
      findsNothing,
    );
    expect(coordinator.cancelPendingCount, 0);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();
    expect(
      find.byKey(const Key('novel-reader-pagination-failure')),
      findsOneWidget,
    );
    expect(coordinator.cancelPendingCount, 1);
    expect(host.scrollChoices, 0);
  });

  testWidgets(
    'a pending navigation reaches its target without replacing the readable page',
    (tester) async {
      final coordinator = _BudgetPaginationCoordinator();
      final host = _BudgetSurfaceHost(
        coordinator,
        targetPageWait: const Duration(seconds: 1),
        backgroundIdle: const Duration(seconds: 1),
      );
      _disposeBudgetHost(tester, coordinator);
      await _pumpBudgetHost(tester, host);
      coordinator.emit(0, pageCount: 2);
      await tester.pump();
      await tester.pump();
      expect(host.navigation.turnNext(), isTrue);
      await tester.pumpAndSettle();
      final pageFinder = find.byKey(const Key('novel-reader-paged-page-view'));
      final pageElement = tester.element(pageFinder);
      expect(
        tester.widget<PageView>(pageFinder).controller!.page,
        closeTo(1, 0.001),
      );

      host.navigationRequest = _budgetNavigation(1, 2);
      await tester.pumpWidget(host.build());
      await tester.pump();
      expect(tester.element(pageFinder), same(pageElement));
      expect(
        tester.widget<PageView>(pageFinder).controller!.page,
        closeTo(1, 0.001),
      );
      expect(
        find.byKey(const Key('novel-reader-pagination-paused')),
        findsOneWidget,
      );

      coordinator.emit(0, pageCount: 3);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.element(pageFinder), same(pageElement));
      expect(
        tester.widget<PageView>(pageFinder).controller!.page,
        closeTo(2, 0.001),
      );
      expect(host.positions.last.pageIndex, 2);
      expect(host.positions.last.isReadOnlyCompatibilityRestore, isFalse);
      expect(host.positions.last.isPageCountFinal, isFalse);
      expect(
        find.byKey(const Key('novel-reader-pagination-paused')),
        findsNothing,
      );
      expect(host.scrollChoices, 0);
      expect(coordinator.cancelPendingCount, 0);
    },
  );

  for (final stop in ['timeout', 'error']) {
    testWidgets('background $stop retains the visible page through retry', (
      tester,
    ) async {
      final coordinator = _BudgetPaginationCoordinator();
      final host = _BudgetSurfaceHost(
        coordinator,
        backgroundIdle: const Duration(seconds: 1),
      );
      _disposeBudgetHost(tester, coordinator);
      await _pumpBudgetHost(tester, host);
      coordinator.emit(0, pageCount: 2);
      await tester.pump();
      await tester.pump();
      expect(host.navigation.turnNext(), isTrue);
      await tester.pumpAndSettle();
      final pageFinder = find.byKey(const Key('novel-reader-paged-page-view'));
      final pageElement = tester.element(pageFinder);
      expect(
        tester.widget<PageView>(pageFinder).controller!.page,
        closeTo(1, 0.001),
      );
      final reports = host.positions.length;
      if (stop == 'timeout') {
        await tester.pump(const Duration(milliseconds: 1100));
      } else {
        coordinator.fail(0);
      }
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('novel-reader-pagination-paused')),
        findsOneWidget,
      );
      expect(tester.element(pageFinder), same(pageElement));
      expect(
        tester.widget<PageView>(pageFinder).controller!.page,
        closeTo(1, 0.001),
      );
      expect(host.positions, hasLength(reports));
      expect(host.scrollChoices, 0);
      await tester.tap(find.byKey(const Key('novel-reader-pagination-retry')));
      await tester.pump();
      expect(coordinator.attempts, hasLength(2));
      expect(tester.element(pageFinder), same(pageElement));
      coordinator.emit(1, pageCount: 1);
      await tester.pump();
      expect(
        tester.widget<PageView>(pageFinder).controller!.page,
        closeTo(1, 0.001),
      );
      coordinator.emit(1, pageCount: 3, isComplete: true);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('novel-reader-pagination-paused')),
        findsNothing,
      );
      expect(tester.element(pageFinder), same(pageElement));
      expect(
        tester.widget<PageView>(pageFinder).controller!.page,
        closeTo(1, 0.001),
      );
      expect(host.positions.last.pageIndex, 1);
      expect(coordinator.clearCount, 0);
      expect(host.scrollChoices, 0);
    });
  }

  testWidgets('background idle resets only when another stable page arrives', (
    tester,
  ) async {
    final coordinator = _BudgetPaginationCoordinator();
    final host = _BudgetSurfaceHost(
      coordinator,
      backgroundIdle: const Duration(milliseconds: 50),
    );
    _disposeBudgetHost(tester, coordinator);
    await _pumpBudgetHost(tester, host);
    coordinator.emit(0, pageCount: 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    coordinator.emit(0, pageCount: 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      find.byKey(const Key('novel-reader-pagination-paused')),
      findsNothing,
    );
    coordinator.emit(0, pageCount: 2, measurementCount: 123);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();
    expect(
      find.byKey(const Key('novel-reader-pagination-paused')),
      findsOneWidget,
    );
    expect(host.scrollChoices, 0);
  });

  testWidgets('active retry replay can exceed the background idle duration', (
    tester,
  ) async {
    final coordinator = _BudgetPaginationCoordinator();
    final host = _BudgetSurfaceHost(
      coordinator,
      backgroundIdle: const Duration(milliseconds: 50),
    );
    _disposeBudgetHost(tester, coordinator);
    await _pumpBudgetHost(tester, host);
    coordinator.emit(0, pageCount: 3);
    await tester.pump();
    await tester.pump();
    final pageFinder = find.byKey(const Key('novel-reader-paged-page-view'));
    final pageElement = tester.element(pageFinder);
    coordinator.fail(0);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('novel-reader-pagination-retry')));
    await tester.pump();
    for (var pageCount = 1; pageCount <= 3; pageCount++) {
      await tester.pump(const Duration(milliseconds: 30));
      coordinator.emit(1, pageCount: pageCount, isComplete: pageCount == 3);
      await tester.pump();
      await tester.pump();
      expect(tester.element(pageFinder), same(pageElement));
      expect(
        tester.widget<PageView>(pageFinder).controller!.page,
        closeTo(0, 0.001),
      );
      expect(
        find.byKey(const Key('novel-reader-pagination-paused')),
        findsNothing,
      );
    }
    expect(coordinator.attempts, hasLength(2));
    expect(coordinator.cancelPendingCount, 2);
    expect(host.positions.last.isPageCountFinal, isTrue);
    expect(host.scrollChoices, 0);
  });

  testWidgets('retry cannot replace a readable prefix with different HTML', (
    tester,
  ) async {
    final coordinator = _BudgetPaginationCoordinator();
    final host = _BudgetSurfaceHost(coordinator);
    _disposeBudgetHost(tester, coordinator);
    await _pumpBudgetHost(tester, host);
    coordinator.emit(0, pageCount: 2);
    await tester.pump();
    await tester.pump();
    final pageFinder = find.byKey(const Key('novel-reader-paged-page-view'));
    final pageElement = tester.element(pageFinder);
    coordinator.fail(0);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('novel-reader-pagination-retry')));
    await tester.pump();
    coordinator.emit(1, pageCount: 3, isComplete: true, replaceFirstHtml: true);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('novel-reader-pagination-paused')),
      findsOneWidget,
    );
    expect(tester.element(pageFinder), same(pageElement));
    expect(find.text('被替换的正文', findRichText: true), findsNothing);
    expect(host.scrollChoices, 0);
  });

  testWidgets(
    'disabled budgets keep an active request waiting without changing modes',
    (tester) async {
      final coordinator = _BudgetPaginationCoordinator();
      final host = _BudgetSurfaceHost(coordinator, enforceBudgets: false);
      _disposeBudgetHost(tester, coordinator);
      await _pumpBudgetHost(tester, host);
      await tester.pump(const Duration(seconds: 10));
      expect(
        find.byKey(const Key('novel-reader-pagination-failure')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-paged-layout-loading')),
        findsOneWidget,
      );
      expect(coordinator.cancelPendingCount, 0);
      expect(host.scrollChoices, 0);
    },
  );

  testWidgets(
    'incremental restore waits for the saved anchor before reporting progress',
    (tester) async {
      final preferences = NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      );
      final theme = ThemeData.light();
      final palette = const NovelReaderThemeResolver().resolve(
        preferences: preferences,
        theme: theme,
      );
      final typography = const NovelReaderTypographyResolver().resolve(
        preferences: preferences,
        theme: theme,
        palette: palette,
      );
      final htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(
        palette,
      );
      final coordinator = _ControlledRestorePaginationCoordinator();
      final positions = <NovelReaderPaginationPosition>[];
      final diagnostics = _RecordingDiagnosticsSink();

      await tester.pumpWidget(
        LocalizedTestApp(
          theme: theme,
          home: Scaffold(
            body: NovelReaderHtmlPagedSurface(
              rawHtml: '<p>第一页</p><p>恢复目标页</p>',
              episode: _episode,
              preferences: preferences,
              typography: typography,
              theme: htmlTheme,
              imageReferer: 'https://bbs.yamibo.com/',
              progressSnapshot: const NovelReaderProgressSnapshot(
                novelId: 'performance-novel',
                episodeId: 'performance-episode',
                flowMode: NovelReaderFlowMode.pagedLtr,
                scrollOffset: 0,
                pageIndex: 1,
                anchorNodeId: 'paragraph-1',
                progressPercent: 0.5,
              ),
              coordinatorBuilder:
                  ({
                    required BuildContext context,
                    required ForumHtmlThemeContext theme,
                    required ForumHtmlReaderPreferences preferences,
                    required String sourceId,
                    required String? threadId,
                    required String? imageCacheOwnerId,
                    required String? imageReferer,
                  }) => coordinator,
              diagnosticsSink: diagnostics,
              onPositionChanged: (position) {
                positions.add(position);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('novel-reader-paged-restoring-position')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('novel-reader-paged-page-view')),
        findsNothing,
      );
      expect(positions, isEmpty);
      expect(diagnostics.records, isEmpty);

      coordinator.emitTargetPage();
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('novel-reader-paged-restoring-position')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-paged-page-view')),
        findsOneWidget,
      );
      expect(positions.map((position) => position.pageIndex), <int>[1]);
      expect(positions.single.isReadOnlyCompatibilityRestore, isTrue);
      final firstFrame = diagnostics.records.single;
      expect(firstFrame.isComplete, isFalse);
      expect(firstFrame.firstPublishedPageDuration, isNotNull);
      expect(
        firstFrame.targetPageAvailableDuration,
        greaterThan(firstFrame.firstPublishedPageDuration!),
      );
      expect(
        firstFrame.firstVisibleFrameDuration,
        greaterThanOrEqualTo(firstFrame.targetPageAvailableDuration),
      );

      coordinator.emitComplete();
      await tester.pump();
      await tester.pump();
      expect(diagnostics.records.map((record) => record.isComplete), <bool>[
        false,
        true,
      ]);
      expect(
        diagnostics.records.last.firstVisibleFrameDuration,
        firstFrame.firstVisibleFrameDuration,
      );
      expect(
        diagnostics.records.last.firstPublishedPageDuration,
        firstFrame.firstPublishedPageDuration,
      );
      expect(
        positions.every((position) => position.isReadOnlyCompatibilityRestore),
        isTrue,
      );
    },
  );

  for (final interaction in ['tap', 'drag', 'seek']) {
    testWidgets(
      'legacy background restore stays read-only until a real $interaction',
      (tester) async {
        final coordinator = _ControlledRestorePaginationCoordinator(
          finalPageCount: 3,
        );
        final navigation = NovelReaderPagedNavigationController();
        NovelReaderPageSeekRequest? seekRequest;
        final positions = <NovelReaderPaginationPosition>[];
        final preferences = NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.pagedLtr,
        );
        final theme = ThemeData.light();
        final palette = const NovelReaderThemeResolver().resolve(
          preferences: preferences,
          theme: theme,
        );
        final typography = const NovelReaderTypographyResolver().resolve(
          preferences: preferences,
          theme: theme,
          palette: palette,
        );
        Widget host() => LocalizedTestApp(
          theme: theme,
          home: Scaffold(
            body: NovelReaderHtmlPagedSurface(
              rawHtml: '<p>第一页</p><p>恢复目标页</p><p>尾页</p>',
              episode: _episode,
              preferences: preferences,
              typography: typography,
              theme: const NovelForumHtmlRenderThemeFactory().fromPalette(
                palette,
              ),
              imageReferer: 'https://bbs.yamibo.com/',
              progressSnapshot: const NovelReaderProgressSnapshot(
                novelId: 'performance-novel',
                episodeId: 'performance-episode',
                flowMode: NovelReaderFlowMode.pagedLtr,
                scrollOffset: 0,
                pageIndex: 0,
                anchorNodeId: 'paragraph-0',
                anchorTextOffset: 777,
                progressPercent: 0.8,
              ),
              navigationController: navigation,
              pageSeekRequest: seekRequest,
              coordinatorBuilder:
                  ({
                    required BuildContext context,
                    required ForumHtmlThemeContext theme,
                    required ForumHtmlReaderPreferences preferences,
                    required String sourceId,
                    required String? threadId,
                    required String? imageCacheOwnerId,
                    required String? imageReferer,
                  }) => coordinator,
              onPositionChanged: positions.add,
            ),
          ),
        );
        await tester.pumpWidget(host());
        await tester.pump();
        await tester.pump();
        expect(positions.last.pageIndex, 0);
        expect(positions.last.isReadOnlyCompatibilityRestore, isTrue);
        coordinator.emitComplete();
        await tester.pump();
        await tester.pump();
        // Completion moves the visible page by the old percentage rule. That
        // programmatic jump must not masquerade as reader confirmation.
        expect(positions.last.pageIndex, 1);
        expect(
          positions.every(
            (position) => position.isReadOnlyCompatibilityRestore,
          ),
          isTrue,
        );
        if (interaction == 'tap') {
          expect(navigation.turnNext(), isTrue);
        } else if (interaction == 'seek') {
          seekRequest = NovelReaderPageSeekRequest(
            requestId: 1,
            episodeId: _episode.episodeId,
            paginationKey: positions.last.paginationKey,
            pageIndex: 1,
          );
          await tester.pumpWidget(host());
        } else {
          await tester.drag(
            find.byKey(const Key('novel-reader-paged-page-view')),
            const Offset(-600, 0),
          );
        }
        await tester.pumpAndSettle();
        expect(positions.last.pageIndex, interaction == 'seek' ? 1 : 2);
        expect(positions.last.isReadOnlyCompatibilityRestore, isFalse);
        expect(positions.last.anchor.formatVersion, 1);
      },
    );
  }
}

const _episode = NovelEpisodeItem(
  episodeId: 'performance-episode',
  novelId: 'performance-novel',
  sourceTid: '6300',
  episodeTitle: '性能降级',
  orderIndex: 0,
);

const _budgetPageTexts = <String>['第一页', '恢复目标页', '尾页'];
const _budgetRawHtml = '<p>第一页</p><p>恢复目标页</p><p>尾页</p>';

NovelReaderAnchorNavigationRequest _budgetNavigation(
  int requestId,
  int index,
) => NovelReaderAnchorNavigationRequest(
  requestId: requestId,
  anchor: NovelReaderTextAnchor(
    episodeId: _episode.episodeId,
    nodeId: 'paragraph-$index',
    formatVersion: 1,
    textIdentity: NovelReaderAnchorFormat.textIdentity(_budgetPageTexts[index]),
  ),
);

Future<void> _pumpBudgetHost(
  WidgetTester tester,
  _BudgetSurfaceHost host,
) async {
  await tester.pumpWidget(host.build());
  await tester.pump();
  await tester.pump();
}

void _disposeBudgetHost(
  WidgetTester tester,
  _BudgetPaginationCoordinator coordinator,
) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await coordinator.close();
  });
}

final class _BudgetSurfaceHost {
  _BudgetSurfaceHost(
    this.coordinator, {
    this.targetPageWait = const Duration(milliseconds: 50),
    this.backgroundIdle = const Duration(milliseconds: 100),
    this.enforceBudgets = true,
    this.preparationService,
  }) {
    theme = ThemeData.light();
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: preferences,
      theme: theme,
    );
    typography = const NovelReaderTypographyResolver().resolve(
      preferences: preferences,
      theme: theme,
      palette: palette,
    );
    htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(palette);
    coordinatorBuilder =
        ({
          required BuildContext context,
          required ForumHtmlThemeContext theme,
          required ForumHtmlReaderPreferences preferences,
          required String sourceId,
          required String? threadId,
          required String? imageCacheOwnerId,
          required String? imageReferer,
        }) => coordinator;
  }

  final _BudgetPaginationCoordinator coordinator;
  final Duration targetPageWait;
  final Duration backgroundIdle;
  final bool enforceBudgets;
  final NovelReaderHtmlPreparationService? preparationService;
  final preferences = NovelReaderPreferences.defaults().copyWith(
    flowMode: NovelReaderFlowMode.pagedLtr,
  );
  late final ThemeData theme;
  late final NovelReaderTypography typography;
  late final ForumHtmlThemeContext htmlTheme;
  late final NovelReaderPaginationCoordinatorBuilder coordinatorBuilder;
  final positions = <NovelReaderPaginationPosition>[];
  final navigation = NovelReaderPagedNavigationController();
  int scrollChoices = 0;
  NovelReaderAnchorNavigationRequest? navigationRequest;
  NovelReaderDocument? semanticDocument;
  NovelReaderPaginationCache? paginationCache;
  NovelReaderPaginationMeasureCache? measureCache;
  NovelReaderComplexHtmlBoundaryCache? boundaryCache;
  NovelReaderPreparedChapterCache? preparedCache;
  bool useDefaultCoordinator = false;
  NovelReaderPaginationDiagnosticsSink diagnosticsSink =
      const NovelReaderNoopPaginationDiagnosticsSink();
  NovelReaderProgressSnapshot snapshot = const NovelReaderProgressSnapshot(
    novelId: 'performance-novel',
    episodeId: 'performance-episode',
    flowMode: NovelReaderFlowMode.pagedLtr,
    scrollOffset: 0,
    pageIndex: 0,
    progressPercent: 0,
  );

  Widget build() => LocalizedTestApp(
    theme: theme,
    home: Scaffold(
      body: NovelReaderHtmlPagedSurface(
        rawHtml: _budgetRawHtml,
        semanticDocument: semanticDocument,
        episode: _episode,
        preferences: preferences,
        typography: typography,
        theme: htmlTheme,
        imageReferer: 'https://bbs.yamibo.com/',
        progressSnapshot: snapshot,
        navigationRequest: navigationRequest,
        navigationController: navigation,
        coordinatorBuilder: useDefaultCoordinator ? null : coordinatorBuilder,
        preparationService: preparationService,
        paginationCache: paginationCache,
        paginationMeasureCache: measureCache,
        paginationBoundaryCache: boundaryCache,
        preparedChapterCache: preparedCache,
        diagnosticsSink: diagnosticsSink,
        performancePolicy: NovelReaderPaginationPerformancePolicy(
          targetPageWait: targetPageWait,
          backgroundIdle: backgroundIdle,
          enforceBudgets: enforceBudgets,
        ),
        onPositionChanged: positions.add,
        onChooseScrollMode: () {
          scrollChoices += 1;
        },
      ),
    ),
  );
}

final class _GatedPreparationService
    implements NovelReaderHtmlPreparationService {
  final requests = <Completer<NovelReaderPreparedChapter>>[];
  final semanticDocuments = <NovelReaderDocument?>[];

  @override
  int get legacyMarkupNormalizerRevision => 1;

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
  }) {
    final request = Completer<NovelReaderPreparedChapter>();
    semanticDocuments.add(semanticDocument);
    requests.add(request);
    return request.future;
  }
}

final class _BudgetPaginationAttempt {
  _BudgetPaginationAttempt(this.chapter, this.key);

  final NovelReaderPreparedChapter chapter;
  final NovelReaderPaginationKey key;
  final controller = StreamController<NovelReaderPaginationProgress>();
}

final class _BudgetPaginationCoordinator
    implements NovelReaderPaginationCoordinator {
  final attempts = <_BudgetPaginationAttempt>[];
  int cancelPendingCount = 0;
  int clearCount = 0;

  @override
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) => Completer<NovelReaderPaginationPlan>().future;

  @override
  Stream<NovelReaderPaginationProgress> paginateIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    final attempt = _BudgetPaginationAttempt(chapter, key);
    attempts.add(attempt);
    return attempt.controller.stream;
  }

  void emit(
    int attemptIndex, {
    required int pageCount,
    bool isComplete = false,
    int measurementCount = 0,
    bool replaceFirstHtml = false,
  }) {
    final attempt = attempts[attemptIndex];
    final pages = <NovelReaderPageFragment>[
      for (var index = 0; index < pageCount; index++)
        _page(attempt, index, replaceFirstHtml: replaceFirstHtml),
    ];
    attempt.controller.add(
      NovelReaderPaginationProgress(
        plan: NovelReaderPaginationPlan(
          key: attempt.key,
          episodeId: attempt.chapter.episodeId,
          pages: pages,
          atomCount: 3,
          measurementCount: measurementCount,
        ),
        isComplete: isComplete,
        processedAtomCount: pageCount,
        totalAtomCount: 3,
      ),
    );
  }

  NovelReaderPageFragment _page(
    _BudgetPaginationAttempt attempt,
    int index, {
    required bool replaceFirstHtml,
  }) {
    final text = _budgetPageTexts[index];
    final start = NovelReaderTextAnchor(
      episodeId: attempt.chapter.episodeId,
      nodeId: 'paragraph-$index',
      formatVersion: 1,
      textIdentity: NovelReaderAnchorFormat.textIdentity(text),
    );
    final end = start.copyWith(textOffset: text.runes.length);
    return NovelReaderPageFragment(
      index: index,
      html: replaceFirstHtml && index == 0 ? '<p>被替换的正文</p>' : '<p>$text</p>',
      startAnchor: start,
      endAnchor: end,
      anchorRanges: [NovelReaderPageAnchorRange(start: start, end: end)],
      imageIndices: const [],
      usedHeight: 80,
      availableHeight: 600,
    );
  }

  void fail(int attemptIndex) {
    attempts[attemptIndex].controller.addError(
      StateError('controlled pagination failure'),
    );
  }

  Future<void> close() async {
    for (final attempt in attempts) {
      await attempt.controller.close();
    }
  }

  @override
  bool isCached(NovelReaderPaginationKey key) => false;

  // Keep the old source alive so tests can release a success/error after the
  // surface has retired that computation. The surface owns its subscription.
  @override
  void cancelPending() {
    cancelPendingCount += 1;
  }

  @override
  void clear() {
    clearCount += 1;
    cancelPending();
  }

  @override
  void clearEpisode(String episodeId) {
    cancelPending();
  }
}

final class _ControlledRestorePaginationCoordinator
    implements NovelReaderPaginationCoordinator {
  _ControlledRestorePaginationCoordinator({this.finalPageCount = 2});

  final int finalPageCount;
  StreamController<NovelReaderPaginationProgress>? _controller;
  NovelReaderPreparedChapter? _chapter;
  NovelReaderPaginationKey? _key;

  @override
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) => Completer<NovelReaderPaginationPlan>().future;

  @override
  Stream<NovelReaderPaginationProgress> paginateIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    _chapter = chapter;
    _key = key;
    late final StreamController<NovelReaderPaginationProgress> controller;
    controller = StreamController<NovelReaderPaginationProgress>(
      onListen: () {
        controller.add(_progress(pageCount: 1));
      },
    );
    _controller = controller;
    return controller.stream;
  }

  void emitTargetPage() {
    _controller?.add(_progress(pageCount: 2));
  }

  void emitComplete() {
    _controller?.add(_progress(pageCount: finalPageCount, isComplete: true));
  }

  NovelReaderPaginationProgress _progress({
    required int pageCount,
    bool isComplete = false,
  }) {
    final chapter = _chapter!;
    final key = _key!;
    final firstStart = NovelReaderTextAnchor(
      episodeId: 'performance-episode',
      nodeId: 'paragraph-0',
      formatVersion: 1,
      textIdentity: NovelReaderAnchorFormat.textIdentity('第一页'),
    );
    final firstEnd = firstStart.copyWith(textOffset: 3);
    final targetStart = NovelReaderTextAnchor(
      episodeId: 'performance-episode',
      nodeId: 'paragraph-1',
      formatVersion: 1,
      textIdentity: NovelReaderAnchorFormat.textIdentity('恢复目标页'),
    );
    final targetEnd = targetStart.copyWith(textOffset: 5);
    final lastStart = NovelReaderTextAnchor(
      episodeId: 'performance-episode',
      nodeId: 'paragraph-2',
      formatVersion: 1,
      textIdentity: NovelReaderAnchorFormat.textIdentity('尾页'),
    );
    final pages = <NovelReaderPageFragment>[
      NovelReaderPageFragment(
        index: 0,
        html: '<p>第一页</p>',
        startAnchor: firstStart,
        endAnchor: firstEnd,
        imageIndices: const <int>[],
        usedHeight: 80,
        availableHeight: 600,
      ),
      if (pageCount > 1)
        NovelReaderPageFragment(
          index: 1,
          html: '<p>恢复目标页</p>',
          startAnchor: targetStart,
          endAnchor: targetEnd,
          imageIndices: const <int>[],
          usedHeight: 80,
          availableHeight: 600,
        ),
      if (pageCount > 2)
        NovelReaderPageFragment(
          index: 2,
          html: '<p>尾页</p>',
          startAnchor: lastStart,
          endAnchor: lastStart.copyWith(textOffset: 2),
          imageIndices: const [],
          usedHeight: 80,
          availableHeight: 600,
        ),
    ];
    return NovelReaderPaginationProgress(
      plan: NovelReaderPaginationPlan(
        key: key,
        episodeId: chapter.episodeId,
        pages: pages,
        atomCount: 3,
      ),
      isComplete: isComplete,
      processedAtomCount: isComplete ? 3 : pageCount,
      totalAtomCount: 3,
    );
  }

  @override
  bool isCached(NovelReaderPaginationKey key) => false;

  @override
  void cancelPending() {
    unawaited(_controller?.close());
  }

  @override
  void clear() => cancelPending();

  @override
  void clearEpisode(String episodeId) => cancelPending();
}

final class _RecordingDiagnosticsSink
    implements NovelReaderPaginationDiagnosticsSink {
  final records = <NovelReaderPaginationDiagnostics>[];

  @override
  void record(NovelReaderPaginationDiagnostics diagnostics) {
    records.add(diagnostics);
  }
}

final class _CompleteRecordingPaginationCoordinator
    implements NovelReaderPaginationCoordinator {
  _CompleteRecordingPaginationCoordinator({this.pageHtml = '<p>安全区分页几何</p>'});

  final String pageHtml;
  NovelReaderPaginationKey? lastKey;

  @override
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) async {
    return _plan(chapter: chapter, key: key);
  }

  @override
  Stream<NovelReaderPaginationProgress> paginateIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    lastKey = key;
    return Stream<NovelReaderPaginationProgress>.value(
      NovelReaderPaginationProgress(
        plan: _plan(chapter: chapter, key: key),
        isComplete: true,
        processedAtomCount: 1,
        totalAtomCount: 1,
      ),
    );
  }

  NovelReaderPaginationPlan _plan({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    final anchor = NovelReaderTextAnchor(
      episodeId: chapter.episodeId,
      nodeId: 'safe-area-paragraph',
    );
    return NovelReaderPaginationPlan(
      key: key,
      episodeId: chapter.episodeId,
      pages: <NovelReaderPageFragment>[
        NovelReaderPageFragment(
          index: 0,
          html: pageHtml,
          startAnchor: anchor,
          endAnchor: anchor,
          imageIndices: const <int>[],
          usedHeight: 80,
          availableHeight: key.viewportHeightPx.toDouble(),
        ),
      ],
      atomCount: 1,
    );
  }

  @override
  bool isCached(NovelReaderPaginationKey key) => false;

  @override
  void cancelPending() {}

  @override
  void clear() {}

  @override
  void clearEpisode(String episodeId) {}
}

class _NoopImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(success: true, cacheKey: request.cacheKey);
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: request.sourcePath,
    );
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async => 0;

  @override
  Future<void> clearUnprotected() async {}
}
