import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/data/services/comic_download_service.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_reading_state_writer.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/comic_reader_page.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_zoomable_image.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> prepareLargeViewport(WidgetTester tester) async {
    // Keep a very tall viewport to make bottom reader controls consistently
    // hittable across different test environments and frame timings.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openReaderMenu(WidgetTester tester) async {
    // The tap-zone keys are geometry anchors; tapping coordinates keeps the
    // test aligned with the pass-through gesture layer.
    final center = tester.getCenter(
      find.byKey(const Key('shared-reader-center-tap-zone')),
    );
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> revealNextChapterTransition(WidgetTester tester) async {
    final listFinder = find.byKey(const Key('comic-reader-image-list'));
    for (var i = 0; i < 4; i++) {
      if (find
          .byKey(const Key('comic-reader-next-chapter-transition'))
          .evaluate()
          .isNotEmpty) {
        return;
      }
      await tester.drag(listFinder, const Offset(0, -1000));
      await tester.pump();
    }
  }

  Future<void> tapVisibleByKey(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    expect(finder, findsOneWidget);
    final center = tester.getCenter(finder);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      Rect.fromLTWH(0, 0, size.width, size.height).contains(center),
      isTrue,
      reason: '$key should be inside the test viewport before tapping',
    );
    await tester.tapAt(center);
  }

  Future<void> dragVisibleByKey(
    WidgetTester tester,
    Key key,
    Offset offset,
  ) async {
    final finder = find.byKey(key);
    expect(finder, findsOneWidget);
    final center = tester.getCenter(finder);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      Rect.fromLTWH(0, 0, size.width, size.height).contains(center),
      isTrue,
      reason: '$key should be inside the test viewport before dragging',
    );
    await tester.dragFrom(center, offset);
  }

  testWidgets('ComicReaderPage renders images and cache actions', (
    tester,
  ) async {
    await prepareLargeViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
          comicReadingStateWriterProvider.overrideWithValue(
            _NoopReadingStateWriter(),
          ),
          comicReaderServiceProvider.overrideWith(
            (ref) async => _ReaderFakeService(),
          ),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(
            comicId: 'yamibo:100',
            episodeId: 'yamibo:100:101',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comic-reader-image-list')), findsOneWidget);
    final listView = tester.widget<ListView>(
      find.byKey(const Key('comic-reader-image-list')),
    );
    // viewportCacheExtentFactor 1.5 × 测试视口高度。
    expect(listView.cacheExtent, 4800);
    expect(
      find.byKey(const Key('shared-reader-center-tap-zone')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shared-reader-top-overlay')), findsOneWidget);
    expect(
      find.byKey(const Key('shared-reader-bottom-overlay')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('comic-reader-page-indicator-overlay')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('comic-reader-next-chapter-transition')),
      findsNothing,
    );

    await openReaderMenu(tester);

    expect(find.byKey(const Key('shared-reader-top-title')), findsOneWidget);
    expect(
      find.byKey(const Key('shared-reader-top-action-bookmark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-top-action-open-thread')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shared-reader-prev-button')), findsOneWidget);
    expect(find.byKey(const Key('shared-reader-next-button')), findsOneWidget);
    expect(
      find.byKey(const Key('shared-reader-bottom-action-mode')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-display')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-cache')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-progress-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-current-label')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shared-reader-total-label')), findsOneWidget);
  });

  testWidgets(
    'ComicReaderPage shows next chapter transition for vertical mode',
    (tester) async {
      await prepareLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            comicRepositoryProvider.overrideWithValue(
              _ReaderFakeRepository(includeNextEpisode: true),
            ),
            comicReadingStateWriterProvider.overrideWithValue(
              _NoopReadingStateWriter(),
            ),
            comicReaderServiceProvider.overrideWith(
              (ref) async => _ReaderFakeService(),
            ),
            comicDownloadServiceProvider.overrideWithValue(
              _NoopComicDownloadService(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
          ],
          child: const MaterialApp(
            home: ComicReaderPage(
              comicId: 'yamibo:100',
              episodeId: 'yamibo:100:101',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await revealNextChapterTransition(tester);

      expect(
        find.byKey(const Key('comic-reader-next-chapter-transition')),
        findsOneWidget,
      );
      expect(find.textContaining('下一章：第2话'), findsOneWidget);
    },
  );

  testWidgets(
    'ComicReaderPage does not flash image loading copy while opening',
    (tester) async {
      await prepareLargeViewport(tester);
      final repository = _ReaderBlockingRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            comicRepositoryProvider.overrideWithValue(repository),
            comicReadingStateWriterProvider.overrideWithValue(
              _NoopReadingStateWriter(),
            ),
            comicReaderServiceProvider.overrideWith(
              (ref) async => _ReaderFakeService(),
            ),
            comicDownloadServiceProvider.overrideWithValue(
              _NoopComicDownloadService(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
          ],
          child: const MaterialApp(
            home: ComicReaderPage(
              comicId: 'yamibo:100',
              episodeId: 'yamibo:100:101',
            ),
          ),
        ),
      );

      await tester.pump();

      expect(
        find.byKey(const Key('comic-reader-page-opening')),
        findsOneWidget,
      );
      expect(find.text('图片加载中'), findsNothing);

      await tester.pump(const Duration(milliseconds: 161));

      expect(find.text('正在打开章节'), findsOneWidget);
    },
  );

  testWidgets(
    'ComicReaderPage uses paged renderer when persisted mode is ltr',
    (tester) async {
      await prepareLargeViewport(tester);
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'reader_pref_mode': 'ltr',
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
            comicReadingStateWriterProvider.overrideWithValue(
              _NoopReadingStateWriter(),
            ),
            comicReaderServiceProvider.overrideWith(
              (ref) async => _ReaderFakeService(),
            ),
            comicDownloadServiceProvider.overrideWithValue(
              _NoopComicDownloadService(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
          ],
          child: const MaterialApp(
            home: ComicReaderPage(
              comicId: 'yamibo:100',
              episodeId: 'yamibo:100:101',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comic-reader-page-view')), findsOneWidget);
      expect(find.byKey(const Key('comic-reader-image-list')), findsNothing);
    },
  );

  testWidgets(
    'ComicReaderPage restores vertical progress only once so top can be reached',
    (tester) async {
      await prepareLargeViewport(tester);
      final repository = _ReaderFakeRepository(
        progress: ComicReadingProgress(
          comicId: 'yamibo:100',
          episodeId: 'yamibo:100:101',
          imageIndex: 1,
          scrollOffset: 500,
          updatedAt: DateTime(2026, 1, 1),
        ),
        images: const <ComicEpisodeImageItem>[
          ComicEpisodeImageItem(
            episodeId: 'yamibo:100:101',
            imageUrl: 'https://img.test/101-1.jpg',
            imageIndex: 0,
            cacheStatus: 'none',
            width: 600,
            height: 1200,
          ),
          ComicEpisodeImageItem(
            episodeId: 'yamibo:100:101',
            imageUrl: 'https://img.test/101-2.jpg',
            imageIndex: 1,
            cacheStatus: 'none',
            width: 600,
            height: 1200,
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            comicRepositoryProvider.overrideWithValue(repository),
            comicReadingStateWriterProvider.overrideWithValue(
              _NoopReadingStateWriter(),
            ),
            comicReaderServiceProvider.overrideWith(
              (ref) async => _ReaderFakeService(),
            ),
            comicDownloadServiceProvider.overrideWithValue(
              _NoopComicDownloadService(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
          ],
          child: const MaterialApp(
            home: ComicReaderPage(
              comicId: 'yamibo:100',
              episodeId: 'yamibo:100:101',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final list = tester.widget<ListView>(
        find.byKey(const Key('comic-reader-image-list')),
      );
      final controller = list.controller!;
      expect(controller.offset, greaterThan(0));

      controller.jumpTo(0);
      await tester.pump();
      await tester.pump();

      expect(controller.offset, 0);
    },
  );

  testWidgets(
    'ComicReaderPage switches from vertical to rtl mode via mode sheet',
    (tester) async {
      await prepareLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
            comicReadingStateWriterProvider.overrideWithValue(
              _NoopReadingStateWriter(),
            ),
            comicReaderServiceProvider.overrideWith(
              (ref) async => _ReaderFakeService(),
            ),
            comicDownloadServiceProvider.overrideWithValue(
              _NoopComicDownloadService(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
          ],
          child: const MaterialApp(
            home: ComicReaderPage(
              comicId: 'yamibo:100',
              episodeId: 'yamibo:100:101',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comic-reader-image-list')), findsOneWidget);

      await openReaderMenu(tester);
      await tapVisibleByKey(
        tester,
        const Key('shared-reader-bottom-action-mode'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('comic-reader-mode-rtl')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comic-reader-page-view')), findsOneWidget);
    },
  );

  testWidgets(
    'ComicReaderPage opens chapter list and display settings sheets',
    (tester) async {
      await prepareLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
            comicReadingStateWriterProvider.overrideWithValue(
              _NoopReadingStateWriter(),
            ),
            comicReaderServiceProvider.overrideWith(
              (ref) async => _ReaderFakeService(),
            ),
            comicDownloadServiceProvider.overrideWithValue(
              _NoopComicDownloadService(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
          ],
          child: const MaterialApp(
            home: ComicReaderPage(
              comicId: 'yamibo:100',
              episodeId: 'yamibo:100:101',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await openReaderMenu(tester);
      await tapVisibleByKey(
        tester,
        const Key('shared-reader-bottom-action-catalog'),
      );
      await tester.pumpAndSettle();

      expect(find.text('章节列表'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('comic-reader-chapter-yamibo:100:101'),
        ),
      );
      await tester.pumpAndSettle();
      await openReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('comic-reader-display-settings-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('comic-reader-page-indicator-switch')),
        findsOneWidget,
      );
    },
  );

  testWidgets('ComicReaderPage more menu can set current page as cover', (
    tester,
  ) async {
    await prepareLargeViewport(tester);
    final repository = _ReaderFakeRepository();
    final imageCache = _FakeImageCacheService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicReadingStateWriterProvider.overrideWithValue(
            _NoopReadingStateWriter(),
          ),
          comicReaderServiceProvider.overrideWith(
            (ref) async => _ReaderFakeService(),
          ),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(imageCache),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(
            comicId: 'yamibo:100',
            episodeId: 'yamibo:100:101',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await openReaderMenu(tester);
    await tapVisibleByKey(tester, const Key('shared-reader-top-action-more'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shared-reader-action-set-cover')));
    // 选区器打开后会显示加载中的图片（测试环境图片不会解析完成，故不能
    // pumpAndSettle——加载圈是常驻动画）。“确定”按钮始终可见，直接确认默认焦点。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.lastCustomCoverLocalPath, '/protected/cover.jpg');
    expect(imageCache.lastLocalCopyRequest?.role, ImageCacheRole.customCover);
  });

  testWidgets(
    'ComicReaderPage updates progress labels after slider interaction',
    (tester) async {
      await prepareLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
            comicReadingStateWriterProvider.overrideWithValue(
              _NoopReadingStateWriter(),
            ),
            comicReaderServiceProvider.overrideWith(
              (ref) async => _ReaderFakeService(),
            ),
            comicDownloadServiceProvider.overrideWithValue(
              _NoopComicDownloadService(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
          ],
          child: const MaterialApp(
            home: ComicReaderPage(
              comicId: 'yamibo:100',
              episodeId: 'yamibo:100:101',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await openReaderMenu(tester);

      expect(
        find.byKey(const Key('shared-reader-current-label')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shared-reader-total-label')),
        findsOneWidget,
      );

      await dragVisibleByKey(
        tester,
        const Key('shared-reader-progress-slider'),
        const Offset(300, 0),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('shared-reader-current-label')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shared-reader-total-label')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ComicReaderPage renders zoomable image wrapper in reader content',
    (tester) async {
      await prepareLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
            comicReadingStateWriterProvider.overrideWithValue(
              _NoopReadingStateWriter(),
            ),
            comicReaderServiceProvider.overrideWith(
              (ref) async => _ReaderFakeService(),
            ),
            comicDownloadServiceProvider.overrideWithValue(
              _NoopComicDownloadService(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
          ],
          child: const MaterialApp(
            home: ComicReaderPage(
              comicId: 'yamibo:100',
              episodeId: 'yamibo:100:101',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ReaderZoomableImage), findsWidgets);
    },
  );

  testWidgets('ComicReaderPage reserves stable slots for vertical images', (
    tester,
  ) async {
    await prepareLargeViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
          comicReadingStateWriterProvider.overrideWithValue(
            _NoopReadingStateWriter(),
          ),
          comicReaderServiceProvider.overrideWith(
            (ref) async => _ReaderFakeService(),
          ),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(
            comicId: 'yamibo:100',
            episodeId: 'yamibo:100:101',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('comic-reader-image-slot-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('comic-reader-image-slot-1')),
      findsOneWidget,
    );
    final slot = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('comic-reader-image-slot-0')),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(slot.constraints.minHeight, greaterThan(0));
  });

  testWidgets(
    'ComicReaderPage uses decoded dimensions for vertical slot reservation',
    (tester) async {
      await prepareLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            comicRepositoryProvider.overrideWithValue(
              _ReaderFakeRepository(
                images: const <ComicEpisodeImageItem>[
                  ComicEpisodeImageItem(
                    episodeId: 'yamibo:100:101',
                    imageUrl: 'https://img.test/tall.jpg',
                    imageIndex: 0,
                    cacheStatus: 'none',
                    width: 600,
                    height: 1800,
                  ),
                ],
              ),
            ),
            comicReadingStateWriterProvider.overrideWithValue(
              _NoopReadingStateWriter(),
            ),
            comicReaderServiceProvider.overrideWith(
              (ref) async => _ReaderFakeService(),
            ),
            comicDownloadServiceProvider.overrideWithValue(
              _NoopComicDownloadService(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
          ],
          child: const MaterialApp(
            home: ComicReaderPage(
              comicId: 'yamibo:100',
              episodeId: 'yamibo:100:101',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final slot = tester.widget<ConstrainedBox>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('comic-reader-image-slot-0'),
              ),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(slot.constraints.minHeight, 3600);
    },
  );

  testWidgets('ComicReaderPage keeps slider stable during jump commit', (
    tester,
  ) async {
    await prepareLargeViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
          comicReadingStateWriterProvider.overrideWithValue(
            _NoopReadingStateWriter(),
          ),
          comicReaderServiceProvider.overrideWith(
            (ref) async => _ReaderFakeService(),
          ),
          comicDownloadServiceProvider.overrideWithValue(
            _NoopComicDownloadService(),
          ),
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
        child: const MaterialApp(
          home: ComicReaderPage(
            comicId: 'yamibo:100',
            episodeId: 'yamibo:100:101',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await openReaderMenu(tester);

    final sliderFinder = find.byKey(const Key('shared-reader-progress-slider'));
    expect(sliderFinder, findsOneWidget);

    await dragVisibleByKey(
      tester,
      const Key('shared-reader-progress-slider'),
      const Offset(280, 0),
    );
    await tester.pump();

    // During commit phase, slider and labels should remain stable and visible.
    expect(
      find.byKey(const Key('shared-reader-progress-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('shared-reader-current-label')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shared-reader-total-label')), findsOneWidget);
  });

  testWidgets(
    'ComicReaderPage reader chrome uses shared palette in dark theme',
    (tester) async {
      await prepareLargeViewport(tester);
      final theme = AppTheme.dark();
      final palette = const ReaderChromePaletteResolver().resolve(theme);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            comicRepositoryProvider.overrideWithValue(_ReaderFakeRepository()),
            comicReadingStateWriterProvider.overrideWithValue(
              _NoopReadingStateWriter(),
            ),
            comicReaderServiceProvider.overrideWith(
              (ref) async => _ReaderFakeService(),
            ),
            comicDownloadServiceProvider.overrideWithValue(
              _NoopComicDownloadService(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _FakeImageCacheService(),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            home: const ComicReaderPage(
              comicId: 'yamibo:100',
              episodeId: 'yamibo:100:101',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await openReaderMenu(tester);

      final topBar = tester.widget<Material>(
        find.byKey(const Key('shared-reader-top-overlay-bar')),
      );
      final bottomPanel = tester.widget<Material>(
        find.byKey(const Key('shared-reader-bottom-overlay-panel')),
      );

      expect(topBar.color, palette.chromeBackground);
      expect(bottomPanel.color, palette.chromeBackground);
    },
  );
}

class _NoopComicDownloadService implements ComicDownloadService {
  @override
  Future<void> deleteEpisodeDownload({
    required String comicId,
    required String episodeId,
  }) async {}

  @override
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ComicEpisodeImageItem>> getDownloadedEpisodeImages({
    required String comicId,
    required String episodeId,
  }) async {
    return const <ComicEpisodeImageItem>[];
  }
}

class _ReaderFakeService implements ComicReaderService {
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
    return ComicImageCacheResult(
      success: true,
      localPath: '/cache/mock.jpg',
      cacheKey: cacheKey,
    );
  }

  @override
  Future<ComicEpisodeImagesFetchResult> fetchEpisodeImages(String tid) async {
    return const ComicEpisodeImagesFetched(<String>[
      'https://img.test/101-1.jpg',
      'https://img.test/101-2.jpg',
    ]);
  }

  @override
  // ignore: deprecated_member_use
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async =>
      (await fetchEpisodeImages(tid)).imageUrlsOrEmpty;

  @override
  Future<void> prefetchImages({required List<String> imageUrls}) async {}
}

class _FakeImageCacheService implements ImageCacheService {
  ImageCacheLocalCopyRequest? lastLocalCopyRequest;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    lastLocalCopyRequest = request;
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: '/protected/cover.jpg',
    );
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: '/cache/mock.jpg',
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
}

class _NoopReadingStateWriter implements ComicReadingStateWriter {
  @override
  Future<bool> isEpisodeRead({
    required String comicId,
    required String episodeId,
  }) async {
    return false;
  }

  @override
  Future<bool> isEpisodeBookmarked({
    required String comicId,
    required String episodeId,
  }) async {
    return false;
  }

  @override
  Future<void> saveProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {}

  @override
  Future<void> markEpisodeCompleted({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
    required DateTime completedAt,
  }) async {}

  @override
  Future<void> setEpisodeRead({
    required String comicId,
    required String episodeId,
    required bool isRead,
    DateTime? readAt,
  }) async {}

  @override
  Future<void> setEpisodeBookmarked({
    required String comicId,
    required String episodeId,
    required bool isBookmarked,
  }) async {}
}

class _ReaderFakeRepository implements ComicRepository, ComicCoverCacheWriter {
  _ReaderFakeRepository({
    this.includeNextEpisode = false,
    ComicReadingProgress? progress,
    List<ComicEpisodeImageItem>? images,
  }) : _progress = progress {
    if (images != null) {
      _episodeImages['yamibo:100:101'] = images;
    }
  }

  final bool includeNextEpisode;
  ComicReadingProgress? _progress;
  String? lastCustomCoverLocalPath;
  final Map<String, List<ComicEpisodeImageItem>> _episodeImages =
      <String, List<ComicEpisodeImageItem>>{
        'yamibo:100:101': const <ComicEpisodeImageItem>[
          ComicEpisodeImageItem(
            episodeId: 'yamibo:100:101',
            imageUrl: 'https://img.test/101-1.jpg',
            imageIndex: 0,
            cacheStatus: 'none',
          ),
          ComicEpisodeImageItem(
            episodeId: 'yamibo:100:101',
            imageUrl: 'https://img.test/101-2.jpg',
            imageIndex: 1,
            cacheStatus: 'none',
          ),
        ],
        'yamibo:100:102': const <ComicEpisodeImageItem>[
          ComicEpisodeImageItem(
            episodeId: 'yamibo:100:102',
            imageUrl: 'https://img.test/102-1.jpg',
            imageIndex: 0,
            cacheStatus: 'none',
          ),
          ComicEpisodeImageItem(
            episodeId: 'yamibo:100:102',
            imageUrl: 'https://img.test/102-2.jpg',
            imageIndex: 1,
            cacheStatus: 'none',
          ),
        ],
      };

  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<void> removeFromShelf({required String comicId}) async {}

  @override
  Future<void> purgeWork({required String comicId}) async {}

  @override
  Future<String> createCategory({required String name}) async => 'mock';

  @override
  Future<void> clearEpisodeImageCache({required String episodeId}) async {
    _episodeImages[episodeId] =
        (_episodeImages[episodeId] ?? const <ComicEpisodeImageItem>[])
            .map(
              (item) => ComicEpisodeImageItem(
                episodeId: item.episodeId,
                imageUrl: item.imageUrl,
                imageIndex: item.imageIndex,
                cacheStatus: 'none',
              ),
            )
            .toList(growable: false);
  }

  @override
  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    lastCustomCoverLocalPath = customCoverLocalPath;
  }

  @override
  Future<void> updateCustomCoverFromLocalFile({
    required String comicId,
    required String localCoverPath,
    String? sourceEpisodeId,
    int? sourceImageIndex,
    String? sourceImageUrl,
    double? focusX,
    double? focusY,
  }) async {
    lastCustomCoverLocalPath = localCoverPath;
  }

  @override
  Future<void> updateCustomCoverFocus({
    required String comicId,
    required double? focusX,
    required double? focusY,
  }) async {}

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return ComicDetail(
      comicId: comicId,
      sourceTid: '100',
      sourceFid: '30',
      title: '测试漫画',
      author: null,
      translationGroup: null,
      coverImageUrl: null,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 1,
    );
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) async {
    final episodes = <ComicEpisodeItem>[
      ComicEpisodeItem(
        episodeId: 'yamibo:100:101',
        comicId: 'yamibo:100',
        episodeTitle: '第1话',
        sourceTid: '101',
        sourceUrl: 'thread-101-1-1.html',
        orderIndex: 0,
        publishTimeText: null,
      ),
    ];
    if (includeNextEpisode) {
      episodes.add(
        const ComicEpisodeItem(
          episodeId: 'yamibo:100:102',
          comicId: 'yamibo:100',
          episodeTitle: '第2话',
          sourceTid: '102',
          sourceUrl: 'thread-102-1-1.html',
          orderIndex: 1,
          publishTimeText: null,
        ),
      );
    }
    episodes.sort(
      (a, b) => descending
          ? b.orderIndex.compareTo(a.orderIndex)
          : a.orderIndex.compareTo(b.orderIndex),
    );
    return episodes;
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({
    required String episodeId,
  }) async {
    return _episodeImages[episodeId] ?? const <ComicEpisodeImageItem>[];
  }

  @override
  Future<List<ComicShelfCategory>> getCategories() async =>
      const <ComicShelfCategory>[];

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({
    required String comicId,
  }) async => _progress;

  @override
  Future<List<ComicShelfItem>> getShelfItems({
    String categoryId = 'default',
  }) async => const <ComicShelfItem>[];

  @override
  Future<bool> isInShelf({required String comicId}) async => false;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return const ComicEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: 0,
    );
  }

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> saveEpisodeImages({
    required String episodeId,
    required List<String> imageUrls,
  }) async {
    _episodeImages[episodeId] = imageUrls
        .asMap()
        .entries
        .map(
          (entry) => ComicEpisodeImageItem(
            episodeId: episodeId,
            imageUrl: entry.value,
            imageIndex: entry.key,
            cacheStatus: 'none',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> updateCustomCover({
    required String comicId,
    required String? customCoverImageUrl,
  }) async {}
  @override
  Future<void> updateCustomMetadata({
    required String comicId,
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  }) async {}
  @override
  Future<void> clearCustomMetadata({
    required String comicId,
    bool title = false,
    bool author = false,
    bool translationGroup = false,
    bool searchTitle = false,
  }) async {}

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {
    final images = _episodeImages[episodeId];
    if (images == null) {
      return;
    }
    _episodeImages[episodeId] = images
        .map(
          (item) => item.imageUrl == imageUrl
              ? ComicEpisodeImageItem(
                  episodeId: item.episodeId,
                  imageUrl: item.imageUrl,
                  imageIndex: item.imageIndex,
                  cacheStatus: cacheStatus,
                  cacheLocalPath: cacheLocalPath,
                )
              : item,
        )
        .toList(growable: false);
  }

  @override
  Future<void> updateGridColumnCount({required int columnCount}) async {}

  @override
  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {
    _progress = ComicReadingProgress(
      comicId: comicId,
      episodeId: episodeId,
      imageIndex: imageIndex,
      scrollOffset: scrollOffset,
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<void> updateCatalogUrl({
    required String comicId,
    required String catalogUrl,
  }) async {}

  @override
  Future<Set<String>> getKnownEpisodeTids({required String comicId}) async =>
      <String>{};
}

class _ReaderBlockingRepository extends _ReaderFakeRepository {
  final Completer<List<ComicEpisodeItem>> _episodesCompleter =
      Completer<List<ComicEpisodeItem>>();

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) {
    return _episodesCompleter.future;
  }
}
