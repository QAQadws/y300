import 'dart:io' as io;

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_reader_view.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/reader_shared/presentation/reader_preferences/reader_preferences_provider.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/thread_image_reader_page.dart';
import 'package:y300/l10n/app_localizations.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_pref_mode': 'vertical',
    });
  });

  testWidgets('ThreadImageReaderPage renders continuous image list', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: LocalizedTestApp(
          home: ThreadImageReaderPage(request: _request()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(ThreadImageReaderPage), findsOneWidget);
    expect(find.byType(ContinuousImageReaderView), findsOneWidget);
    expect(find.byKey(const Key('thread-image-reader-list')), findsOneWidget);
    expect(find.byType(CachedLibraryImage), findsWidgets);
    expect(find.byType(ReaderSessionImage), findsWidgets);
  });

  testWidgets(
    'ThreadImageReaderPage applies live shared spacing over request snapshots',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(
              _RecordingImageCacheService(),
            ),
          ],
          child: LocalizedTestApp(
            home: ThreadImageReaderPage(request: _request()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The request fixture deliberately carries the old fixed 10dp gap.
      // The shared preference default (0dp) must win at render time.
      expect(
        _verticalReaderView(tester).items.map((item) => item.spacingAfter),
        everyElement(0),
      );
      expect(_verticalSlotGap(tester, 0, 1), closeTo(0, 0.5));

      await _openReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await _pumpReaderUiTransition(tester);

      tester
          .widget<Slider>(
            find.byKey(const Key('comic-reader-page-spacing-slider')),
          )
          .onChanged!
          .call(24);
      await tester.pump();
      await tester.pump();
      expect(
        _verticalReaderView(tester).items.map((item) => item.spacingAfter),
        everyElement(24),
      );
      expect(_verticalSlotGap(tester, 0, 1), closeTo(24, 0.5));

      tester
          .widget<Slider>(
            find.byKey(const Key('comic-reader-page-spacing-slider')),
          )
          .onChanged!
          .call(48);
      await tester.pump();
      await tester.pump();
      expect(
        _verticalReaderView(tester).items.map((item) => item.spacingAfter),
        everyElement(48),
      );
      expect(_verticalSlotGap(tester, 0, 1), closeTo(48, 0.5));
    },
  );

  testWidgets(
    'ThreadImageReaderPage preserves its vertical anchor when spacing changes',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recorder = _RecordingContinuousImageDiagnosticRecorder();
      final precacheService = _RecordingForumImagePrecacheService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(
              _RecordingImageCacheService(),
            ),
            forumImagePrecacheServiceProvider.overrideWithValue(
              precacheService,
            ),
          ],
          child: LocalizedTestApp(
            home: ThreadImageReaderPage(
              request: _request(),
              diagnosticRecorder: recorder,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final list = tester.widget<ListView>(
        find.byKey(const Key('thread-image-reader-list')),
      );
      list.controller!.jumpTo(1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final indicator = tester.widget<Text>(
        find.byKey(const Key('comic-reader-page-indicator-text')),
      );
      final logicalIndex =
          int.parse(indicator.data!.split('/').first.trim()) - 1;
      final anchor = find.byKey(
        ValueKey<String>('thread-image-reader-image-slot-$logicalIndex'),
      );
      final anchorTopBefore = tester.getTopLeft(anchor).dy;
      final preloadCountBefore = precacheService.decodedSpecs.length;

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ThreadImageReaderPage)),
      );
      await container
          .read(readerPreferencesControllerProvider.notifier)
          .setPageSpacing(24);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      expect(tester.getTopLeft(anchor).dy, closeTo(anchorTopBefore, 1));
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('comic-reader-page-indicator-text')),
            )
            .data,
        indicator.data,
      );
      expect(precacheService.decodedSpecs, hasLength(preloadCountBefore));
      expect(
        recorder.events
            .where(
              (event) =>
                  event.type ==
                  ContinuousImageDiagnosticEventType.readerSessionCreated,
            )
            .length,
        1,
      );
    },
  );

  testWidgets('ThreadImageReaderPage uses the shared default LTR snapshot', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(
            _RecordingImageCacheService(),
          ),
        ],
        child: LocalizedTestApp(
          home: ThreadImageReaderPage(request: _request()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      find.byKey(const Key('thread-image-reader-page-view')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('thread-image-reader-list')), findsNothing);
    expect(
      tester
          .widget<PageView>(
            find.byKey(const Key('thread-image-reader-page-view')),
          )
          .reverse,
      isFalse,
    );
  });

  testWidgets('ThreadImageReaderPage exposes general reading chrome only', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: LocalizedTestApp(
          home: ThreadImageReaderPage(request: _request()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 打开 overlay 菜单（点击中央 tap 区）。
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('shared-reader-center-tap-zone'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump(const Duration(milliseconds: 300));

    // 通用阅读能力：滑块 / 页码标签 / 显示设置入口。
    expect(
      find.byKey(const Key('shared-reader-progress-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-current-label')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-display')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-export-current-image')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-export-current-image')),
      findsOneWidget,
    );

    // detail 强相关项不应出现：书签 / 原帖 / 章节 / 缓存 / 翻章。
    expect(
      find.byKey(const Key('shared-reader-top-action-bookmark')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('shared-reader-top-action-open-thread')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-cache')),
      findsNothing,
    );
    // 翻章按钮属于共享进度条 chrome，帖子图片阅读器没有"上一话/下一话"语义，
    // 因此它们存在但被禁用（onPressed == null）。
    final prevButton = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-prev-button')),
    );
    final nextButton = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-next-button')),
    );
    expect(prevButton.onPressed, isNull);
    expect(nextButton.onPressed, isNull);
  });

  testWidgets('ThreadImageReaderPage preloads reader session images', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();
    final precacheService = _RecordingForumImagePrecacheService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(cacheService),
          forumImagePrecacheServiceProvider.overrideWithValue(precacheService),
        ],
        child: LocalizedTestApp(
          home: ThreadImageReaderPage(request: _request()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(precacheService.decodedSpecs, isNotEmpty);
    expect(
      precacheService.decodedSpecs.map((spec) => spec.kind).toSet(),
      <ForumImageKind>{ForumImageKind.threadInline},
    );
    expect(
      precacheService.decodedSpecs.map((spec) => spec.retentionClass).toSet(),
      <ImageRetentionClass>{ImageRetentionClass.recentReader},
    );
    expect(precacheService.decodedSpecs.first.ownerId, 'thread:100:post:p1');
    expect(precacheService.decodedSpecs.first.cacheKey, 'thread/inline/page-1');
  });

  testWidgets(
    'ThreadImageReaderPage vertical slider lands on exact item anchor',
    (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'reader_pref_mode': 'vertical',
      });
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recorder = _RecordingContinuousImageDiagnosticRecorder();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(
              _RecordingImageCacheService(),
            ),
          ],
          child: LocalizedTestApp(
            home: ThreadImageReaderPage(
              request: _request(),
              diagnosticRecorder: recorder,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await _openReaderMenu(tester);

      final slider = find.byKey(const Key('shared-reader-progress-slider'));
      final sliderRect = tester.getRect(slider);
      await tester.tapAt(sliderRect.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      final target = find.byKey(
        const ValueKey<String>('thread-image-reader-image-slot-2'),
      );
      expect(target, findsOneWidget);
      expect(tester.getTopLeft(target).dy, closeTo(0, 1));
      expect(
        recorder.events.any(
          (event) =>
              event.type == ContinuousImageDiagnosticEventType.seekReached &&
              event.targetIndex == 2 &&
              event.elapsedMs != null &&
              event.correctionDelta != null,
        ),
        isTrue,
      );
    },
  );

  for (final mode in <String>['ltr', 'rtl']) {
    testWidgets(
      'ThreadImageReaderPage $mode uses logical indexes for swipe and taps',
      (tester) async {
        await _pumpHorizontalReader(tester, mode: mode);
        final controller = _pageController(tester);
        expect(controller.page, closeTo(2, 0.01));

        await tester.drag(
          find.byKey(const Key('thread-image-reader-page-view')),
          Offset(mode == 'ltr' ? -900 : 900, 0),
        );
        await _pumpReaderUiTransition(tester);
        expect(controller.page, closeTo(3, 0.01));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('shared-reader-top-subtitle')))
              .data,
          '4 / 5',
        );

        await _tapReaderZone(
          tester,
          mode == 'ltr'
              ? const Key('shared-reader-left-tap-zone')
              : const Key('shared-reader-right-tap-zone'),
        );
        expect(controller.page, closeTo(2, 0.01));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('shared-reader-top-subtitle')))
              .data,
          '3 / 5',
        );

        await _tapReaderZone(
          tester,
          mode == 'ltr'
              ? const Key('shared-reader-right-tap-zone')
              : const Key('shared-reader-left-tap-zone'),
        );
        expect(controller.page, closeTo(3, 0.01));
      },
    );

    testWidgets(
      'ThreadImageReaderPage $mode slider previews a non-initial target',
      (tester) async {
        final recorder = _RecordingContinuousImageDiagnosticRecorder();
        await _pumpHorizontalReader(
          tester,
          mode: mode,
          diagnosticRecorder: recorder,
        );
        await _openReaderMenu(tester);

        final slider = find.byKey(const Key('shared-reader-progress-slider'));
        final gesture = await tester.startGesture(tester.getCenter(slider));
        await gesture.moveBy(Offset(tester.getSize(slider).width * 0.42, 0));
        await tester.pump();

        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('shared-reader-current-label')),
              )
              .data,
          '5',
        );
        await gesture.up();
        await tester.pump();
        await tester.pump();

        expect(
          recorder.events.any(
            (event) =>
                event.type ==
                    ContinuousImageDiagnosticEventType.readerSessionCreated &&
                event.ownerId == 'thread:100:post:p1' &&
                event.index == 2,
          ),
          isTrue,
        );
        expect(
          recorder.events.any(
            (event) =>
                event.type ==
                    ContinuousImageDiagnosticEventType
                        .initialRestoreCompleted &&
                event.generation != null &&
                event.status == 'consumed',
          ),
          isTrue,
        );
        expect(
          recorder.events.any(
            (event) =>
                event.type == ContinuousImageDiagnosticEventType.seekStarted &&
                event.mode == mode &&
                event.generation == 1 &&
                event.targetIndex == 4 &&
                event.result == 'pending',
          ),
          isTrue,
        );
        expect(
          recorder.events.any(
            (event) =>
                event.type == ContinuousImageDiagnosticEventType.seekReached &&
                event.generation == 1 &&
                event.targetIndex == 4,
          ),
          isTrue,
        );
      },
    );

    for (final targetIndex in <int>[0, 4]) {
      testWidgets('ThreadImageReaderPage $mode slider seek remains at page '
          '${targetIndex + 1}', (tester) async {
        await _pumpHorizontalReader(tester, mode: mode);
        await _openReaderMenu(tester);
        final slider = find.byKey(const Key('shared-reader-progress-slider'));
        final gesture = await tester.startGesture(tester.getCenter(slider));
        final direction = targetIndex == 0 ? -1.0 : 1.0;
        await gesture.moveBy(
          Offset(tester.getSize(slider).width * 0.42 * direction, 0),
        );
        await tester.pump();
        expect(find.text('${targetIndex + 1}'), findsWidgets);

        await gesture.up();
        await tester.pump();
        expect(_pageController(tester).page, closeTo(targetIndex, 0.01));

        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tapAt(
          tester.getCenter(
            find.byKey(const Key('shared-reader-center-tap-zone')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 330));
        await tester.pump(const Duration(milliseconds: 300));

        expect(_pageController(tester).page, closeTo(targetIndex, 0.01));
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('shared-reader-current-label')),
              )
              .data,
          '${targetIndex + 1}',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('shared-reader-top-subtitle')))
              .data,
          '${targetIndex + 1} / 5',
        );
      });
    }
  }

  testWidgets(
    'ThreadImageReaderPage confirms side taps at 220ms and settles smoothly',
    (tester) async {
      await _pumpHorizontalReader(tester, mode: 'ltr');
      final controller = _pageController(tester);
      expect(controller.page, closeTo(2, 0.01));

      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('shared-reader-right-tap-zone'))),
      );
      await tester.pump(const Duration(milliseconds: 219));
      expect(controller.page, closeTo(2, 0.01));

      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.page, greaterThan(2));
      expect(controller.page, lessThan(3));

      await tester.pump(const Duration(milliseconds: 90));
      expect(controller.page, closeTo(3, 0.01));
    },
  );

  testWidgets(
    'ThreadImageReaderPage keeps side-zone double tap zoom without turning',
    (tester) async {
      final recorder = _RecordingContinuousImageDiagnosticRecorder();
      await _pumpHorizontalReader(
        tester,
        mode: 'ltr',
        diagnosticRecorder: recorder,
      );
      final controller = _pageController(tester);
      final right = tester.getCenter(
        find.byKey(const Key('shared-reader-right-tap-zone')),
      );

      await tester.tapAt(right);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(right);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));

      expect(controller.page, closeTo(2, 0.01));
      expect(
        recorder.events.any(
          (event) =>
              event.type == ContinuousImageDiagnosticEventType.zoomActivated,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'ThreadImageReaderPage mode switch keeps committed logical page',
    (tester) async {
      await _pumpHorizontalReader(tester, mode: 'ltr');
      await tester.drag(
        find.byKey(const Key('thread-image-reader-page-view')),
        const Offset(-900, 0),
      );
      await _pumpReaderUiTransition(tester);
      expect(_pageController(tester).page, closeTo(3, 0.01));

      await _openReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await _pumpReaderUiTransition(tester);
      final l10n = AppLocalizations.of(
        tester.element(
          find.byKey(const Key('comic-reader-display-settings-sheet')),
        ),
      );
      await tester.tap(find.text(l10n.readerModeRtl));
      await tester.pump(const Duration(milliseconds: 350));
      Navigator.of(
        tester.element(
          find.byKey(const Key('comic-reader-display-settings-sheet')),
        ),
      ).pop();
      await _pumpReaderUiTransition(tester);

      final pageView = tester.widget<PageView>(
        find.byKey(const Key('thread-image-reader-page-view')),
      );
      expect(pageView.reverse, isTrue);
      expect(pageView.controller!.page, closeTo(3, 0.01));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('shared-reader-top-subtitle')))
            .data,
        '4 / 5',
      );
    },
  );

  testWidgets(
    'ThreadImageReaderPage records preload tasks without duplicates',
    (tester) async {
      final recorder = _RecordingContinuousImageDiagnosticRecorder();
      final precacheService = _RecordingForumImagePrecacheService();
      await _pumpHorizontalReader(
        tester,
        mode: 'ltr',
        diagnosticRecorder: recorder,
        precacheService: precacheService,
      );
      await tester.pump();

      final scheduled = recorder.events
          .where(
            (event) =>
                event.type ==
                ContinuousImageDiagnosticEventType.prefetchScheduled,
          )
          .toList(growable: false);
      final completed = recorder.events
          .where(
            (event) =>
                event.type ==
                ContinuousImageDiagnosticEventType.prefetchCompleted,
          )
          .toList(growable: false);
      final taskIdentities = scheduled
          .map((event) => '${event.itemId}:${event.preloadKind}')
          .toSet();

      expect(scheduled, isNotEmpty);
      expect(scheduled.length, lessThanOrEqualTo(7));
      expect(completed, hasLength(scheduled.length));
      expect(scheduled.length - taskIdentities.length, 0);
      expect(scheduled.map((event) => event.readerKind).toSet(), <String>{
        'thread',
      });
      final modes = scheduled.map((event) => event.mode).toSet();
      expect(modes, contains('ltr'));
      expect(modes.difference(<String>{'vertical', 'ltr'}), isEmpty);
      expect(completed.every((event) => event.applied == true), isTrue);
    },
  );

  testWidgets('ThreadImageReaderPage double tap zoom does not show overlay', (
    tester,
  ) async {
    final recorder = _RecordingContinuousImageDiagnosticRecorder();
    await _pumpHorizontalReader(
      tester,
      mode: 'ltr',
      diagnosticRecorder: recorder,
    );
    final center = tester.getCenter(
      find.byKey(const Key('shared-reader-center-tap-zone')),
    );

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 360));

    final topGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    final bottomGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-bottom-overlay-hit-test-gate')),
    );
    expect(topGate.ignoring, isTrue);
    expect(bottomGate.ignoring, isTrue);
    expect(
      recorder.events.any(
        (event) =>
            event.type == ContinuousImageDiagnosticEventType.zoomActivated,
      ),
      isTrue,
    );
    expect(
      tester
          .widget<PageView>(
            find.byKey(const Key('thread-image-reader-page-view')),
          )
          .physics,
      isA<PageScrollPhysics>(),
    );
    final zoomedPage = _pageController(tester).page;
    await tester.dragFrom(center, const Offset(-900, 0));
    await _pumpReaderUiTransition(tester);
    expect(_pageController(tester).page, closeTo(zoomedPage!, 0.01));

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 360));

    expect(
      recorder.events.any(
        (event) =>
            event.type == ContinuousImageDiagnosticEventType.zoomDeactivated,
      ),
      isTrue,
    );
    expect(
      tester
          .widget<IgnorePointer>(
            find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
          )
          .ignoring,
      isTrue,
    );
    expect(
      tester
          .widget<PageView>(
            find.byKey(const Key('thread-image-reader-page-view')),
          )
          .physics,
      isA<PageScrollPhysics>(),
    );
    await tester.drag(
      find.byKey(const Key('thread-image-reader-page-view')),
      const Offset(-900, 0),
    );
    await _pumpReaderUiTransition(tester);
    expect(_pageController(tester).page, closeTo(3, 0.01));
  });
}

ThreadImageOpenRequest _request({int initialIndex = 0, int count = 5}) {
  final items = List<ContinuousImageItem>.generate(count, (index) {
    final page = index + 1;
    return ContinuousImageItem(
      ownerId: 'thread:100:post:p1',
      id: 'thread:100:post:p1:$index:thread/inline/page-$page',
      url: 'https://bbs.yamibo.com/data/attachment/forum/page-$page.jpg',
      cacheKey: 'thread/inline/page-$page',
      index: index,
      sourceKind: ContinuousImageSourceKind.threadImageReader,
      knownWidth: 200,
      knownHeight: 120,
      knownDimensionSource: ContinuousImageDimensionSource.html,
      fallbackAspectRatio: 0.7,
      spacingAfter: 10,
    );
  });
  return ThreadImageOpenRequest(
    tid: '100',
    pid: 'p1',
    postNumber: 1,
    referer: 'https://bbs.yamibo.com/thread-100-1-1.html',
    group: const ThreadPostImageGroup(
      tid: '100',
      pid: 'p1',
      postNumber: 1,
      entries: <ThreadPostImageEntry>[],
    ),
    initialIndex: initialIndex,
    continuousImages: items,
  );
}

Future<void> _pumpHorizontalReader(
  WidgetTester tester, {
  required String mode,
  ContinuousImageDiagnosticRecorder diagnosticRecorder =
      const NoopContinuousImageDiagnosticRecorder(),
  ForumImagePrecacheService? precacheService,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'reader_pref_mode': mode,
  });
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imageCacheServiceProvider.overrideWithValue(
          _RecordingImageCacheService(),
        ),
        if (precacheService != null)
          forumImagePrecacheServiceProvider.overrideWithValue(precacheService),
      ],
      child: LocalizedTestApp(
        home: ThreadImageReaderPage(
          request: _request(initialIndex: 2),
          diagnosticRecorder: diagnosticRecorder,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

PageController _pageController(WidgetTester tester) {
  final pageView = tester.widget<PageView>(
    find.byKey(const Key('thread-image-reader-page-view')),
  );
  return pageView.controller!;
}

ContinuousImageReaderView _verticalReaderView(WidgetTester tester) {
  return tester.widget<ContinuousImageReaderView>(
    find.byType(ContinuousImageReaderView),
  );
}

double _verticalSlotGap(WidgetTester tester, int first, int second) {
  final firstRect = tester.getRect(
    find.byKey(ValueKey<String>('thread-image-reader-image-slot-$first')),
  );
  final secondRect = tester.getRect(
    find.byKey(ValueKey<String>('thread-image-reader-image-slot-$second')),
  );
  return secondRect.top - firstRect.bottom;
}

Future<void> _openReaderMenu(WidgetTester tester) async {
  await tester.tapAt(
    tester.getCenter(find.byKey(const Key('shared-reader-center-tap-zone'))),
  );
  await tester.pump(const Duration(milliseconds: 330));
  await tester.pump(const Duration(milliseconds: 260));
}

Future<void> _pumpReaderUiTransition(WidgetTester tester) async {
  // Reader images may keep a loading indicator active independently from the
  // page, zoom, or settings animation under test.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 32));
}

Future<void> _tapReaderZone(WidgetTester tester, Key key) async {
  await tester.tapAt(tester.getCenter(find.byKey(key)));
  await tester.pump(const Duration(milliseconds: 330));
  await _pumpReaderUiTransition(tester);
}

class _RecordingContinuousImageDiagnosticRecorder
    implements ContinuousImageDiagnosticRecorder {
  final events = <ContinuousImageDiagnosticEvent>[];

  @override
  bool get enabled => true;

  @override
  void recordContinuousImage(ContinuousImageDiagnosticEvent event) {
    events.add(event);
  }
}

class _RecordingImageCacheService implements ImageCacheService {
  final requests = <ImageCacheRequest>[];
  final getCachedKeys = <String>[];

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    requests.add(request);
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: io.File('assets/noavatar.png').absolute.path,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    getCachedKeys.add(cacheKey);
    return null;
  }

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
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

class _RecordingForumImagePrecacheService implements ForumImagePrecacheService {
  final decodedSpecs = <ForumImageLoadSpec>[];
  final diskSpecs = <ForumImageLoadSpec>[];

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async {
    diskSpecs.add(spec);
    return ForumImagePrecacheResult(
      success: true,
      cacheKey: spec.cacheKey,
      localPath: io.File('assets/noavatar.png').absolute.path,
    );
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async {
    decodedSpecs.add(spec);
    return ForumImagePrecacheResult(
      success: true,
      decoded: true,
      cacheKey: spec.cacheKey,
      localPath: io.File('assets/noavatar.png').absolute.path,
    );
  }
}
