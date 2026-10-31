import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
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
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reading_body_sliver.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_surface.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

import '../../../test_support/localized_test_app.dart';

const _work = 'novel:49:100';
const _chapter = 'novel:49:100:5001';
const _next = 'novel:49:100:5002';
const _args = NovelReaderArgs(novelId: _work, episodeId: _chapter);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'controlled native entry renders and commits through the reader',
    (tester) async {
      final repository = _ReadingRepository(_nativeLongBody);
      await tester.pumpWidget(_app(repository, nativePagination: true));
      await _pumpNativeReady(tester);
      expect(find.byType(NovelReaderHtmlPagedSurface), findsNothing);
      expect(
        find.byKey(const Key('novel-reader-delayed-loading-surface')),
        findsNothing,
      );
      final native = tester.widget<NovelReaderNativePagedSurface>(
        find.byType(NovelReaderNativePagedSurface),
      );
      final controller = _nativeController(tester);
      expect(native.resolvedFont.id, native.preferences.fontFamily);
      expect(controller.snapshot!.length, greaterThan(2));
      expect(controller.visiblePageIndex, 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter]!.anchorFormatVersion, 1);
      expect(
        repository.progress[_chapter]!.paginationKey,
        controller.paginationKey,
      );
      expect(repository.completed, isEmpty);
      final owner = native.owner;
      await tester.pumpWidget(const SizedBox());
      expect(owner.isClosed, isTrue);
      expect(owner.activeCacheHandles, 0);
      expect(owner.estimatedRetainedBytes, 0);
    },
  );

  testWidgets('native completion waits for the actual menu slide out', (
    tester,
  ) async {
    final repository = _ReadingRepository('<p>完整而短的一章。</p>');
    await tester.pumpWidget(_app(repository, nativePagination: true));
    await _pumpNativeReady(tester);
    final overlay = tester
        .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
        .controller!;
    final controller = _nativeController(tester);
    overlay.showMenu();
    expect(controller.isSuspended, isTrue);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.completed, isEmpty);

    overlay.hideMenu();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.isSuspended, isTrue);
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 120));
    await _pumpNativeReady(tester);
    expect(_nativeController(tester), same(controller));
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 249));
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(repository.completed, [_chapter]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native lifecycle pauses work before an inactive frame', (
    tester,
  ) async {
    final repository = _ReadingRepository('<p>暂停前的短章。</p>');
    await tester.pumpWidget(_app(repository, nativePagination: true));
    await _pumpNativeReady(tester);
    final controller = _nativeController(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(controller.isSuspended, isTrue);
    await tester.pump(const Duration(hours: 1));
    expect(repository.completed, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpNativeReady(tester);
    expect(_nativeController(tester), same(controller));
    expect(repository.completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(repository.completed, [_chapter]);
    await tester.pumpWidget(const SizedBox());
  });

  for (final lifecycle in [false, true]) {
    testWidgets('frameless native hide/resume keeps the qualified flush lease '
        '(lifecycle: $lifecycle)', (tester) async {
      final repository = _ReadingRepository(_nativeLongBody);
      await tester.pumpWidget(_app(repository, nativePagination: true));
      await _pumpNativeReady(tester);
      final gate = repository.commitGate = Completer<void>();
      if (lifecycle) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        final overlay = tester
            .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
            .controller!;
        overlay.showMenu();
        overlay.hideMenu();
      }
      await _pumpNativeReady(tester);
      expect(repository.committed, isEmpty);
      expect(repository.completed, isEmpty);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter]!.anchorFormatVersion, 1);
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final rtl in [false, true]) {
    testWidgets('native side tap closes the menu and turns once (rtl: $rtl)', (
      tester,
    ) async {
      final repository = _ReadingRepository(_nativeLongBody);
      await tester.pumpWidget(
        _app(
          repository,
          nativePagination: true,
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: rtl
                ? NovelReaderFlowMode.pagedRtl
                : NovelReaderFlowMode.pagedLtr,
          ),
        ),
      );
      await _pumpNativeReady(tester);
      final overlayFinder = find.byType(ReaderOverlayScaffold);
      tester
          .widget<ReaderOverlayScaffold>(overlayFinder)
          .controller!
          .showMenu();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      final overlay = tester.widget<ReaderOverlayScaffold>(overlayFinder);
      (rtl ? overlay.onLeftTap : overlay.onRightTap)!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_nativeController(tester).visiblePageIndex, 0);
      await tester.pump(const Duration(milliseconds: 120));
      await _pumpNativeReady(tester, page: 1, advanceTime: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter]!.pageIndex, 1);
      expect(_nativeController(tester).visiblePageIndex, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('native slider request closes the menu before actual arrival', (
    tester,
  ) async {
    final repository = _ReadingRepository(_nativeLongBody);
    await tester.pumpWidget(_app(repository, nativePagination: true));
    await _pumpNativeReady(tester);
    final overlayFinder = find.byType(ReaderOverlayScaffold);
    tester.widget<ReaderOverlayScaffold>(overlayFinder).controller!.showMenu();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    tester
        .widget<ReaderOverlayScaffold>(overlayFinder)
        .bottomBar
        .progress!
        .onChangeEnd(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_nativeController(tester).visiblePageIndex, 0);
    await tester.pump(const Duration(milliseconds: 120));
    await _pumpNativeReady(tester, page: 2);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.progress[_chapter]!.pageIndex, 2);
    expect(
      tester
          .widget<ReaderOverlayScaffold>(overlayFinder)
          .bottomBar
          .progress!
          .interactionLocked,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final seek in [false, true]) {
    testWidgets('new pointer retires a turn waiting for menu dismissal '
        '(seek: $seek)', (tester) async {
      final repository = _ReadingRepository(_nativeLongBody);
      await tester.pumpWidget(_app(repository, nativePagination: true));
      await _pumpNativeReady(tester);
      final overlayFinder = find.byType(ReaderOverlayScaffold);
      tester
          .widget<ReaderOverlayScaffold>(overlayFinder)
          .controller!
          .showMenu();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      final overlay = tester.widget<ReaderOverlayScaffold>(overlayFinder);
      if (seek) {
        overlay.bottomBar.progress!.onChangeEnd(2);
      } else {
        overlay.onRightTap!();
      }
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(NovelReaderNativePagedSurface)),
      );
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 240));
      await _pumpNativeReady(tester, page: 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_nativeController(tester).visiblePageIndex, 0);
      expect(
        tester
            .widget<ReaderOverlayScaffold>(overlayFinder)
            .bottomBar
            .progress!
            .interactionLocked,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'native menu flush failure retires completion and reports the error',
    (tester) async {
      final repository = _ReadingRepository('<p>保存失败后仍可阅读的短章。</p>');
      await tester.pumpWidget(_app(repository, nativePagination: true));
      await _pumpNativeReady(tester);
      repository.failNextCommit = true;
      tester
          .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
          .controller!
          .showMenu();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(_nativeController(tester).isSuspended, isTrue);
      expect(repository.completed, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('native reflow retains the reading owner and mounted shell', (
    tester,
  ) async {
    final repository = _ReadingRepository(_nativeLongBody);
    await tester.pumpWidget(_app(repository, nativePagination: true));
    await _pumpNativeReady(tester);
    final surfaceFinder = find.byType(NovelReaderNativePagedSurface);
    final shellState = tester.state(surfaceFinder);
    final owner = tester
        .widget<NovelReaderNativePagedSurface>(surfaceFinder)
        .owner;
    final oldController = _nativeController(tester);
    final overlay = tester
        .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
        .controller!;
    overlay.showMenu();
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovelReaderPage)),
      listen: false,
    );
    final reader = container.read(
      novelReaderControllerProvider(_args).notifier,
    );
    reader.previewPreferences(
      container
          .read(novelReaderControllerProvider(_args))
          .requireValue
          .preferences
          .copyWith(fontSize: 28),
    );
    await tester.pump();
    expect(tester.state(surfaceFinder), same(shellState));
    expect(
      tester.widget<NovelReaderNativePagedSurface>(surfaceFinder).owner,
      same(owner),
    );
    expect(oldController.isSuspended, isTrue);
    expect(repository.completed, isEmpty);
    overlay.hideMenu();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await _pumpNativeReady(tester);
    expect(_nativeController(tester), isNot(same(oldController)));
    expect(oldController.isClosed, isTrue);
    expect(tester.state(surfaceFinder), same(shellState));
    expect(
      tester
          .widget<NovelReaderNativePagedSurface>(surfaceFinder)
          .preferences
          .fontSize,
      28,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'native failure preserves the mode until explicit scroll choice',
    (tester) async {
      final repository = _ReadingRepository('<p>不会被自动旧渲染器接管的正文。</p>');
      final preparation = _NativePreparationProbe()..fail = true;
      await tester.pumpWidget(
        _app(
          repository,
          nativePagination: true,
          nativePreparation: preparation,
        ),
      );
      for (
        var frame = 0;
        frame < 100 &&
            find
                .byKey(const Key('novel-reader-pagination-fallback'))
                .evaluate()
                .isEmpty;
        frame++
      ) {
        await tester.pump();
      }
      expect(
        find.byKey(const Key('novel-reader-pagination-fallback')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(preparation.calls, 1);
      expect(find.byType(NovelReaderHtmlPagedSurface), findsNothing);
      expect(repository.committed, isEmpty);
      expect(
        tester
            .widget<NovelReaderNativePagedSurface>(
              find.byType(NovelReaderNativePagedSurface),
            )
            .preferences
            .flowMode,
        NovelReaderFlowMode.pagedLtr,
      );
      await tester.tap(
        find.byKey(const Key('novel-reader-pagination-fallback')),
      );
      await _pumpBodyWithoutAdvancingTime(tester);
      expect(find.byType(NovelReaderNativePagedSurface), findsNothing);
      expect(
        find.byKey(const Key('novel-reader-paragraph-list')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final hideWithRoute in [false, true]) {
    testWidgets('late native preparation cannot report under a hidden reader '
        '(route: $hideWithRoute)', (tester) async {
      final repository = _ReadingRepository('<p>等待准备时遮挡的完整短章。</p>');
      final preparation = _NativePreparationProbe()..gate = Completer<void>();
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          repository,
          nativePagination: true,
          nativePreparation: preparation,
          navigation: navigation,
        ),
      );
      for (var frame = 0; frame < 100 && preparation.calls == 0; frame++) {
        await tester.pump();
      }
      expect(preparation.calls, 1);
      if (hideWithRoute) {
        unawaited(
          navigation.currentState!.push<void>(
            MaterialPageRoute(builder: (_) => const Scaffold(body: SizedBox())),
          ),
        );
        await tester.pump();
      } else {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      preparation.gate!.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.committed, isEmpty);
      expect(repository.completed, isEmpty);
      if (hideWithRoute) {
        navigation.currentState!.pop();
        await tester.pumpAndSettle();
      } else {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await _pumpNativeReady(tester);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(repository.completed, [_chapter]);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'source menu actual body reading returns to the latest common position',
    (tester) async {
      final repository = _ReadingRepository(
        '<div style="height: 1800px">小说与原帖公共正文。</div>',
      );
      final sourceRepository = _SourceThreadRepository(repository.html);
      final locator = _SourcePostLocator();
      await tester.pumpWidget(
        _app(repository, threadRepository: sourceRepository, locator: locator),
      );
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      final before = _verticalPosition(tester).pixels;
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('novel-reader-paragraph-list'))),
      );
      await tester.pump(const Duration(milliseconds: 330));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('shared-reader-top-action-open-thread')),
      );
      await tester.pumpAndSettle();
      final sourcePage = tester.widget<ThreadDetailPage>(
        find.byType(ThreadDetailPage),
      );
      expect(sourcePage.targetPid, '5001');
      expect(sourcePage.landing, ThreadPostLanding.top);
      expect(sourcePage.bodyReadingObserver, isNotNull);
      expect(locator.calls, 1);
      final priorSource = repository.progress[_chapter]!;
      expect(priorSource.progressPercent, greaterThan(0));
      final sourceScroll = find.descendant(
        of: find.byType(ThreadDetailPage),
        matching: find.byType(CustomScrollView),
      );
      await tester.drag(sourceScroll, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final sourceProgress = repository.progress[_chapter]!;
      expect(
        sourceProgress.progressPercent,
        greaterThan(priorSource.progressPercent),
      );
      expect(
        sourceProgress.percentBasis,
        NovelProgressPercentBasis.bodyGeometryV1,
      );
      expect(sourceProgress.anchorNodeId, isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final geometry = _bodyLayout(tester);
      final expected =
          geometry.bodyTop +
          sourceProgress.progressPercent * geometry.bodyRange -
          geometry.topChrome;
      expect(_verticalPosition(tester).pixels, closeTo(expected, 1));
      expect(_verticalPosition(tester).pixels, greaterThan(before));
      expect(repository.progress[_chapter], same(sourceProgress));
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unchanged paged return retires old navigation without remounting HTML',
    (tester) async {
      final repository = _ReadingRepository(
        List.generate(
          16,
          (index) => '<p>第$index段：${List.filled(40, '小说正文').join()}。</p>',
        ).join(),
      );
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          repository,
          navigation: navigation,
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.pagedLtr,
          ),
          threadRepository: _SourceThreadRepository(repository.html),
          locator: _SourcePostLocator(),
        ),
      );
      await _pumpPagedReady(tester);
      final surfaceFinder = find.byType(NovelReaderHtmlPagedSurface);
      tester
          .widget<NovelReaderHtmlPagedSurface>(surfaceFinder)
          .navigationController!
          .turnNext();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final mountedSurface = tester.state(surfaceFinder);
      final before = _state(tester);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 330));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('shared-reader-top-action-open-thread')),
      );
      await tester.pumpAndSettle();
      final sourceOtherChapter = NovelReadingProgress(
        novelId: _work,
        episodeId: _next,
        scrollOffset: 0,
        progressPercent: .2,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime(2026, 10, 8),
      );
      await repository.commitProgress(progress: sourceOtherChapter);
      final commitCount = repository.committed.length;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final surface = tester.widget<NovelReaderHtmlPagedSurface>(surfaceFinder);
      surface.onImagesReadyChanged!(true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.state(surfaceFinder), same(mountedSurface));
      expect(
        _state(tester).readingSurfaceRevision,
        before.readingSurfaceRevision,
      );
      expect(repository.recent, _next);
      expect(repository.committed, hasLength(commitCount));
      surface.navigationController!.turnNext();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.recent, _chapter);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'source body percentage restores the actual paged surface read-only',
    (tester) async {
      final repository = _ReadingRepository(
        List.generate(
          16,
          (index) => '<p>第$index段：${List.filled(40, '小说正文').join()}。</p>',
        ).join(),
      );
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          repository,
          navigation: navigation,
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.pagedLtr,
          ),
        ),
      );
      await _pumpPagedReady(tester);
      final controller = _controller(tester);
      final handoff = controller.beginSourceReadingHandoff()!;
      unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('原帖'))),
        ),
      );
      await tester.pumpAndSettle();
      final source = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 0,
        progressPercent: .6,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime(2026, 10, 8),
      );
      await repository.commitProgress(progress: source);
      final commitCount = repository.committed.length;
      await controller.acceptSourceReadingReturn(handoff);
      navigation.currentState!.pop();
      await _pumpPagedReady(tester);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      final pageView = tester.widget<PageView>(
        find.byKey(const Key('novel-reader-paged-page-view')),
      );
      final count = pageView.childrenDelegate.estimatedChildCount!;
      expect(count, greaterThan(1));
      expect(pageView.controller!.page, (.6 * count).floor().toDouble());
      expect(repository.progress[_chapter], same(source));
      expect(repository.committed, hasLength(commitCount));
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'source handoff returns to the latest body position without rewriting it',
    (tester) async {
      final repository = _ReadingRepository(
        '<div style="height: 2000px">原帖往返正文。</div>',
      );
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(repository, navigation: navigation));
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      final controller = _controller(tester);
      await controller.saveCurrentProgressNow(_state(tester).progressSnapshot);
      final revision = _state(tester).readingSurfaceRevision;
      final handoff = controller.beginSourceReadingHandoff()!;
      unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('原帖'))),
        ),
      );
      await tester.pumpAndSettle();
      final source = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 0,
        progressPercent: .65,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime(2026, 10, 8),
      );
      await repository.commitProgress(progress: source);
      final commitCount = repository.committed.length;
      await controller.acceptSourceReadingReturn(handoff);
      navigation.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      final geometry = _bodyLayout(tester);
      final expected =
          geometry.bodyTop + .65 * geometry.bodyRange - geometry.topChrome;
      expect(_verticalPosition(tester).pixels, closeTo(expected, 1));
      expect(_state(tester).readingSurfaceRevision, revision + 1);
      expect(_state(tester).progressSnapshot.progressPercent, .65);
      expect(repository.committed, hasLength(commitCount));
      expect(repository.progress[_chapter], same(source));
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.progress[_chapter], same(source));
    },
  );

  testWidgets(
    'source reset returns to the head without establishing a new position',
    (tester) async {
      final repository = _ReadingRepository(
        '<div style="height: 1600px">原帖重置正文。</div>',
      );
      repository.progress[_chapter] = NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 0,
        progressPercent: .5,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime(2026, 10, 1),
      );
      repository.recent = _chapter;
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(repository, navigation: navigation));
      await _pumpBodyWithoutAdvancingTime(tester);
      await tester.pumpAndSettle();
      expect(_verticalPosition(tester).pixels, greaterThan(0));
      final controller = _controller(tester);
      final handoff = controller.beginSourceReadingHandoff()!;
      unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('原帖'))),
        ),
      );
      await tester.pumpAndSettle();
      repository.progress.clear();
      repository.recent = null;
      await controller.acceptSourceReadingReturn(handoff);
      navigation.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_verticalPosition(tester).pixels, 0);
      expect(repository.progress, isEmpty);
      expect(repository.committed, isEmpty);
      expect(repository.completed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
          ModalRoute.of(tester.element(find.byType(NovelReaderPage)))!
              .isCurrent,
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

NovelReaderController _controller(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(NovelReaderPage)),
      listen: false,
    ).read(novelReaderControllerProvider(_args).notifier);

Future<void> _pumpPagedReady(WidgetTester tester) async {
  for (var frame = 0; frame < 200; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    final surface = find.byType(NovelReaderHtmlPagedSurface);
    if (surface.evaluate().isNotEmpty &&
        tester
                .widget<NovelReaderHtmlPagedSurface>(surface)
                .paginationCache!
                .length >
            0 &&
        find
            .byKey(const Key('novel-reader-paged-page-view'))
            .evaluate()
            .isNotEmpty) {
      return;
    }
  }
  fail('Final paged layout did not become ready');
}

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
  NovelReaderPreferences? preferences,
  ThreadRepository? threadRepository,
  ThreadPostLocator? locator,
  EdgeInsets safeArea = EdgeInsets.zero,
  bool nativePagination = false,
  NovelReaderNativePreparationService? nativePreparation,
}) => ProviderScope(
  overrides: [
    novelRepositoryProvider.overrideWithValue(repository),
    novelReaderPreferencesRepositoryProvider.overrideWithValue(
      _ReadingPreferences()
        ..preferences =
            preferences ??
            NovelReaderPreferences.defaults().copyWith(
              flowMode: nativePagination
                  ? NovelReaderFlowMode.pagedLtr
                  : NovelReaderFlowMode.vertical,
            ),
    ),
    novelChapterInteractionsDockPreferencesRepositoryProvider.overrideWithValue(
      _DisabledDock(),
    ),
    libraryStateRepositoryProvider.overrideWithValue(_UnusedLibraryState()),
    forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
    imageCacheServiceProvider.overrideWithValue(images ?? _PendingImageCache()),
    if (preparation != null)
      novelReaderHtmlPreparationServiceProvider.overrideWithValue(preparation),
    if (nativePreparation != null)
      novelReaderNativePreparationServiceProvider.overrideWithValue(
        nativePreparation,
      ),
    if (threadRepository != null)
      threadRepositoryProvider.overrideWithValue(threadRepository),
    if (locator != null) threadPostLocatorProvider.overrideWithValue(locator),
  ],
  child: LocalizedTestApp(
    navigatorKey: navigation,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(padding: safeArea, viewPadding: safeArea),
      child: child!,
    ),
    home: NovelReaderPage(
      novelId: _work,
      initialEpisodeId: _chapter,
      nativePagination: nativePagination,
      nativeIdleScheduler: _nativeIdle,
    ),
  ),
);

Future<void> _nativeIdle() async {}

final _nativeLongBody = List.generate(
  16,
  (index) => '<p>第$index段：${List.filled(40, '小说正文').join()}。</p>',
).join();

NovelReaderNativePagedController _nativeController(WidgetTester tester) =>
    tester
        .widget<NovelReaderNativePagedViewport>(
          find.byType(NovelReaderNativePagedViewport).last,
        )
        .controller;

Future<void> _pumpNativeReady(
  WidgetTester tester, {
  int? page,
  bool advanceTime = false,
}) async {
  for (var frame = 0; frame < 250; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(
      advanceTime ? const Duration(milliseconds: 16) : Duration.zero,
    );
    if (find.byType(NovelReaderNativePagedViewport).evaluate().isEmpty) {
      continue;
    }
    final controller = _nativeController(tester);
    if (!controller.isSuspended &&
        controller.snapshot?.isComplete == true &&
        controller.visiblePageIndex != null &&
        (page == null || controller.visiblePageIndex == page) &&
        !controller.hasPendingNavigation) {
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return;
    }
  }
  fail('The native reading page did not confirm the requested visible page');
}

class _NativePreparationProbe implements NovelReaderNativePreparationService {
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<NovelReaderNativeChapterPreparation> prepare({
    required String episodeId,
    required String sourceId,
    required String rawHtml,
    required NovelReaderDocument semanticDocument,
    required NovelReaderPaginationCancellationToken cancellation,
    TextConverter converter = const IdentityTextConverter(),
  }) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('test native preparation failure');
    return const DefaultNovelReaderNativePreparationService().prepare(
      episodeId: episodeId,
      sourceId: sourceId,
      rawHtml: rawHtml,
      semanticDocument: semanticDocument,
      cancellation: cancellation,
      converter: converter,
    );
  }
}

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
  Completer<void>? commitGate;
  bool failNextCommit = false;

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
    final gate = commitGate;
    if (gate != null) await gate.future;
    if (failNextCommit) {
      failNextCommit = false;
      throw StateError('test progress commit failure');
    }
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

class _SourcePostLocator implements ThreadPostLocator {
  var calls = 0;
  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) async {
    calls++;
    return ApiSuccess(ThreadPostLocation(tid: tid, pid: pid, page: 2, url: ''));
  }
}

class _SourceThreadRepository implements ThreadRepository {
  _SourceThreadRepository(this.html);
  final String html;
  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;
  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async => DataReadSuccess(
    data: ThreadDetailData(
      tid: tid,
      fid: '49',
      subject: '测试作品',
      author: 'author',
      replies: 0,
      views: 1,
      currentPage: page,
      perPage: 20,
      posts: [
        ThreadPost(
          pid: '5001',
          author: 'author',
          authorId: '10',
          message: html,
          number: 21,
          isFirst: false,
          dateline: '',
        ),
      ],
    ),
    capabilities: capabilities.toReadCapabilities(),
    metadata: const DataReadMetadata.network(),
  );
}
