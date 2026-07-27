import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_episode_open_policy.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_update_service.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_supplemental_hydration_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

void main() {
  testWidgets('NovelReaderPage shows immersive menu from center tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildReaderApp(repository: _FakeNovelRepository()),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-paragraph-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('novel-reader-episode-selector')),
      findsNothing,
    );

    var topGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(topGate.ignoring, isTrue);

    await _showReaderMenu(tester);

    topGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(topGate.ignoring, isFalse);
    expect(find.text('测试小说'), findsOneWidget);
    final subtitle = tester.widget<Text>(
      find.byKey(const Key('shared-reader-top-subtitle')),
    );
    expect(subtitle.data, '第1章');
  });

  testWidgets('NovelReaderPage hides menu after content scroll', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(
          firstParagraphs: List<String>.generate(30, (index) => '第一章段落 $index'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);

    var topGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(topGate.ignoring, isFalse);

    await tester.drag(
      find.byKey(const Key('novel-reader-paragraph-list')),
      const Offset(0, -180),
    );
    await tester.pump();

    topGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(topGate.ignoring, isTrue);
  });

  testWidgets(
    'NovelReaderPage first drag does not get reset by restore logic',
    (tester) async {
      await tester.pumpWidget(
        _buildReaderApp(
          repository: _FakeNovelRepository(
            firstParagraphs: List<String>.generate(
              30,
              (index) => '第一章段落 $index',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final list = find.byKey(const Key('novel-reader-paragraph-list'));
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);

      await tester.drag(list, const Offset(0, -80));
      await tester.pumpAndSettle();

      final scrollableState = tester.state<ScrollableState>(scrollable);
      final firstOffset = scrollableState.position.pixels;
      expect(firstOffset, greaterThan(0));

      await tester.drag(list, const Offset(0, -80));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('novel-reader-paragraph-list')),
        findsOneWidget,
      );
      expect(scrollableState.position.pixels, greaterThan(firstOffset));
    },
  );

  testWidgets(
    'NovelReaderPage restores vertical progress after HTML content is ready',
    (tester) async {
      final repository = _FakeNovelRepository(
        firstParagraphs: List<String>.generate(
          60,
          (index) => '第一章恢复测试段落 $index',
        ),
        readingProgress: NovelReadingProgress(
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5001',
          scrollOffset: 320,
          updatedAt: DateTime(2026, 7, 21),
          progressPercent: 0.25,
        ),
      );

      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: find.byKey(const Key('novel-reader-paragraph-list')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;

      expect(position.maxScrollExtent, greaterThan(320));
      expect(position.pixels, closeTo(320, 0.01));
      expect(repository.readingProgress?.scrollOffset, closeTo(320, 0.01));
    },
  );

  testWidgets(
    'vertical progress survives exit and a new continue-reading session',
    (tester) async {
      final repository = _FakeNovelRepository(
        firstParagraphs: List<String>.generate(
          60,
          (index) => '第一章往返测试段落 $index',
        ),
      );
      await tester.pumpWidget(
        _buildReaderApp(
          repository: repository,
          home: const _NovelReaderRoundTripHost(),
        ),
      );

      await tester.tap(find.byKey(const Key('open-novel-from-beginning')));
      await tester.pumpAndSettle();
      await _showReaderMenu(tester);
      final firstSlider = tester.widget<Slider>(
        find.byKey(const Key('shared-reader-progress-slider')),
      );
      firstSlider.onChangeStart?.call(0.59);
      firstSlider.onChanged?.call(0.59);
      firstSlider.onChangeEnd?.call(0.59);
      await tester.pumpAndSettle();

      expect(repository.readingProgress?.progressPercent, closeTo(0.59, 0.01));
      final savedOffset = repository.readingProgress!.scrollOffset;
      expect(savedOffset, greaterThan(0));

      await tester.tap(find.byKey(const Key('shared-reader-top-back-button')));
      await tester.pumpAndSettle();
      expect(find.byType(NovelReaderPage), findsNothing);

      await tester.tap(find.byKey(const Key('continue-novel-reading')));
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: find.byKey(const Key('novel-reader-paragraph-list')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, closeTo(savedOffset, 0.01));

      await _showReaderMenu(tester);
      expect(find.text('59%'), findsOneWidget);
    },
  );

  testWidgets('NovelReaderPage opens catalog and switches chapter', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      chapterLoadDelay: const Duration(milliseconds: 120),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-chapter-list-sheet')),
      findsOneWidget,
    );
    expect(find.text('当前'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('novel-reader-chapter-novel:49:100:5002')),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('novel-reader-transition-mask')),
      findsOneWidget,
    );
    expect(_readerText('第一段。'), findsOneWidget);
    expect(
      find.byKey(const Key('novel-reader-transition-indicator')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();

    expect(_readerText('第三段。'), findsOneWidget);
    expect(_readerText('第一段。'), findsNothing);
    expect(repository.savedProgressEpisodeIds, contains('novel:49:100:5001'));
  });

  testWidgets(
    'NovelReaderPage catalog searches chapters and shows empty state',
    (tester) async {
      final repository = _FakeNovelRepository.threeEpisodes();
      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await tester.pumpAndSettle();

      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-catalog')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('novel-reader-chapter-search-field')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('novel-reader-chapter-search-field')),
        '第3章',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('novel-reader-chapter-novel:49:100:5003')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('novel-reader-chapter-novel:49:100:5001')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const Key('novel-reader-chapter-search-field')),
        '5002',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('novel-reader-chapter-novel:49:100:5002')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('novel-reader-chapter-novel:49:100:5003')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const Key('novel-reader-chapter-search-field')),
        '不存在',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('novel-reader-chapter-search-empty')),
        findsOneWidget,
      );
    },
  );

  testWidgets('NovelReaderPage catalog marks last reading episode', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes(
      readingProgress: NovelReadingProgress(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5003',
        scrollOffset: 120,
        updatedAt: DateTime(2026, 6, 1),
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
    );
    await tester.pumpAndSettle();

    expect(find.text('上次阅读'), findsOneWidget);
  });

  testWidgets('NovelReaderPage catalog opens near current chapter', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.manyEpisodes(
      count: 20,
      currentIndex: 14,
    );
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        initialEpisodeId: 'novel:49:100:5015',
      ),
    );
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-chapter-novel:49:100:5015')),
      findsOneWidget,
    );
    expect(find.text('当前'), findsOneWidget);
    expect(
      find.byKey(const Key('novel-reader-chapter-novel:49:100:5001')),
      findsNothing,
    );
  });

  testWidgets('NovelReaderPage bottom menu shows progress and chapter nav', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    expect(
      find.byKey(const Key('shared-reader-progress-slider')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shared-reader-prev-button')), findsOneWidget);
    expect(find.byKey(const Key('shared-reader-next-button')), findsOneWidget);
    final verticalSlider = tester.widget<Slider>(
      find.byKey(const Key('shared-reader-progress-slider')),
    );
    expect(verticalSlider.divisions, isNull);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shared-reader-prev-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shared-reader-next-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-bookmark')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('shared-reader-top-action-bookmark')),
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

    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-display')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-show-progress-switch')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('novel-reader-show-chapter-title-switch')),
      findsNothing,
    );
  });

  testWidgets('vertical progress slider seeks once on release', (tester) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: List<String>.generate(30, (index) => '滚动进度段落 $index'),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();
    await _showReaderMenu(tester);

    final slider = tester.widget<Slider>(
      find.byKey(const Key('shared-reader-progress-slider')),
    );
    slider.onChangeStart?.call(0.5);
    slider.onChanged?.call(0.5);
    slider.onChangeEnd?.call(0.5);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.lastSavedOffset, greaterThan(0));
    expect(repository.readingProgress?.progressPercent, closeTo(0.5, 0.01));
  });

  testWidgets('NovelReaderPage transition chrome follows reader palette', (
    tester,
  ) async {
    final theme = AppTheme.dark();
    final chromePalette = const ReaderChromePaletteResolver().resolve(theme);
    final repository = _FakeNovelRepository.threeEpisodes(
      chapterLoadDelay: const Duration(milliseconds: 120),
    );
    await tester.pumpWidget(
      _buildReaderApp(repository: repository, theme: theme),
    );
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('novel-reader-chapter-novel:49:100:5002')),
    );
    await tester.pump();

    final mask = tester.widget<ColoredBox>(
      find.byKey(const Key('novel-reader-transition-mask')),
    );
    final indicator = tester.widget<DecoratedBox>(
      find.byKey(const Key('novel-reader-transition-indicator')),
    );
    final decoration = indicator.decoration as BoxDecoration;

    expect(mask.color, chromePalette.overlayScrim.withValues(alpha: 0.18));
    expect(decoration.color, chromePalette.transitionCardBackground);

    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'NovelReaderPage reader chrome uses shared palette in dark theme',
    (tester) async {
      final theme = AppTheme.dark();
      final palette = const ReaderChromePaletteResolver().resolve(theme);
      final repository = _FakeNovelRepository();
      await tester.pumpWidget(
        _buildReaderApp(repository: repository, theme: theme),
      );
      await tester.pumpAndSettle();

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

  testWidgets(
    'NovelReaderPage chapter switch failure keeps old content and shows snackbar',
    (tester) async {
      final repository = _FakeNovelRepository.threeEpisodes(
        failedEpisodeIds: const <String>{'novel:49:100:5002'},
        chapterLoadDelay: const Duration(milliseconds: 120),
      );
      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await tester.pumpAndSettle();

      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-catalog')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('novel-reader-chapter-novel:49:100:5002')),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('novel-reader-transition-mask')),
        findsOneWidget,
      );
      expect(_readerText('第一段。'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 140));
      await tester.pumpAndSettle();

      expect(_readerText('第一段。'), findsOneWidget);
      expect(_readerText('第三段。'), findsNothing);
      expect(find.text('章节切换失败，已保留当前章节'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'NovelReaderPage display sheet is half height and applies theme live',
    (tester) async {
      final repository = _FakeNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          themePreset: NovelReaderThemePreset.light,
        ),
      );
      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await tester.pumpAndSettle();

      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('novel-theme-sepia')), findsOneWidget);
      expect(
        find.byKey(const Key('novel-reader-display-settings-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('novel-reader-flow-mode-control')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('novel-reader-content-width-slider')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-paragraph-spacing-slider')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-page-padding-slider')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-first-line-indent-slider')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-font-weight-control')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-text-align-control')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-display-settings-save')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-display-settings-cancel')),
        findsNothing,
      );

      final sheetHeight = tester
          .getSize(find.byKey(const Key('novel-reader-display-settings-sheet')))
          .height;
      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(sheetHeight, lessThanOrEqualTo(viewportHeight * 0.5 + 1));

      await tester.ensureVisible(find.byKey(const Key('novel-theme-sepia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-theme-sepia')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(repository.latestPreferences?.themeMode, 'sepia');
      expect(
        repository.latestPreferences?.themePreset,
        NovelReaderThemePreset.sepia,
      );
      expect(repository.upsertPreferencesCallCount, 1);
    },
  );

  testWidgets('NovelReaderPage display sheet exposes paged modes', (
    tester,
  ) async {
    final repository = _FakeNovelRepository();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-display')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-flow-mode-control')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('novel-reader-conversion-mode-control')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('novel-reader-safe-area-switch')),
      findsOneWidget,
    );
    expect(find.text('分页 LTR'), findsOneWidget);
    expect(find.text('分页 RTL'), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-paged-page-view')), findsNothing);
    expect(
      find.byKey(const Key('novel-reader-paragraph-list')),
      findsOneWidget,
    );
    expect(repository.latestPreferences, isNull);
  });

  testWidgets(
    'NovelReaderPage display sheet slider applies without save button',
    (tester) async {
      final repository = _FakeNovelRepository();
      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await tester.pumpAndSettle();

      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('novel-reader-display-settings-save')),
        findsNothing,
      );

      await tester.drag(
        find.descendant(
          of: find.byKey(const Key('novel-reader-font-size-slider')),
          matching: find.byType(Slider),
        ),
        const Offset(120, 0),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(repository.latestPreferences, isNotNull);
      expect(repository.latestPreferences?.fontSize, isNot(18.5));
      expect(repository.upsertPreferencesCallCount, 1);
    },
  );

  testWidgets('NovelReaderPage persists the safe area display switch', (
    tester,
  ) async {
    final repository = _FakeNovelRepository();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-display')),
    );
    await tester.pumpAndSettle();

    final safeAreaSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('novel-reader-safe-area-switch')),
    );
    expect(safeAreaSwitch.value, isTrue);

    await tester.ensureVisible(
      find.byKey(const Key('novel-reader-safe-area-switch')),
    );
    await tester.tap(find.byKey(const Key('novel-reader-safe-area-switch')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(repository.latestPreferences?.safeAreaEnabled, isFalse);
    expect(repository.upsertPreferencesCallCount, 1);
  });

  testWidgets(
    'NovelReaderPage display sheet barrier dismiss keeps applied settings',
    (tester) async {
      final repository = _FakeNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          themePreset: NovelReaderThemePreset.light,
        ),
      );
      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await tester.pumpAndSettle();

      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('novel-theme-sepia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-theme-sepia')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(
        repository.latestPreferences?.themePreset,
        NovelReaderThemePreset.sepia,
      );

      await tester.tapAt(const Offset(24, 24));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('novel-reader-display-settings-sheet')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-paged-page-view')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-paragraph-list')),
        findsOneWidget,
      );
      expect(
        repository.latestPreferences?.themePreset,
        NovelReaderThemePreset.sepia,
      );
      expect(repository.upsertPreferencesCallCount, 1);
    },
  );

  testWidgets('NovelReaderPage renders the saved paged preference', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
      firstParagraphs: List<String>.generate(
        12,
        (index) => '首屏分页段落 $index ${List<String>.filled(60, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-paragraph-list')), findsNothing);
    expect(
      find.byKey(const Key('novel-reader-html-document-view')),
      findsNothing,
    );
    expect(find.byKey(const Key('novel-reader-paged-surface')), findsOneWidget);
    expect(
      find.byKey(const Key('novel-reader-paged-page-view')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('novel-reader-page-indicator-text')),
      findsOneWidget,
    );
    final contentInset = tester.widget<Padding>(
      find.byKey(const ValueKey<String>('novel-reader-paged-content-inset-0')),
    );
    expect(
      (contentInset.padding as EdgeInsets).bottom,
      greaterThan(18),
      reason: 'The page indicator reserves only its compact text footprint.',
    );
    final indicatorText = tester.widget<Text>(
      find.byKey(const Key('novel-reader-page-indicator-text')),
    );
    expect(indicatorText.style?.fontSize, 11);
    expect(
      find.ancestor(
        of: find.byKey(const Key('novel-reader-page-indicator-text')),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    expect(
      tester
          .getBottomLeft(
            find.byKey(const ValueKey<String>('novel-reader-paged-page-0')),
          )
          .dy,
      lessThanOrEqualTo(
        tester
            .getTopLeft(find.byKey(const Key('novel-reader-page-indicator')))
            .dy,
      ),
    );

    await _showReaderMenu(tester);
    final pagedSlider = tester.widget<Slider>(
      find.byKey(const Key('shared-reader-progress-slider')),
    );
    expect(pagedSlider.divisions, isNotNull);
    expect(find.text('计算中'), findsNothing);
    pagedSlider.onChangeStart?.call(pagedSlider.max);
    pagedSlider.onChanged?.call(pagedSlider.max);
    pagedSlider.onChangeEnd?.call(pagedSlider.max);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repository.readingProgress?.pageIndex, pagedSlider.max.toInt());
    expect(repository.readingProgress?.pageCount, pagedSlider.max.toInt() + 1);
  });

  testWidgets('NovelReaderPage persists paged mode across reconstruction', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: List<String>.generate(
        12,
        (index) => '持久化分页段落 $index ${List<String>.filled(60, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-display')),
    );
    await tester.pumpAndSettle();
    final pagedLtr = find.byKey(
      const ValueKey<String>('reader-segment-分页 LTR'),
    );
    await tester.ensureVisible(pagedLtr);
    await tester.tap(pagedLtr);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(repository.preferences.flowMode, NovelReaderFlowMode.pagedLtr);
    expect(
      find.byKey(const Key('novel-reader-paged-page-view')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-paragraph-list')), findsNothing);
    expect(
      find.byKey(const Key('novel-reader-paged-page-view')),
      findsOneWidget,
    );
  });

  testWidgets('NovelReaderPage restores a visible page for the same layout', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
      firstParagraphs: List<String>.generate(
        36,
        (index) => '持久化分页段落 $index ${List<String>.filled(120, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    final pageViewFinder = find.byKey(
      const Key('novel-reader-paged-page-view'),
    );
    await tester.drag(pageViewFinder, const Offset(-700, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 260));

    final savedIndex = repository.readingProgress?.pageIndex;
    expect(savedIndex, greaterThan(0));
    expect(repository.readingProgress?.paginationKey, isNotNull);
    expect(repository.readingProgress?.anchorNodeId, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.textContaining('${savedIndex! + 1} /'), findsOneWidget);
  });

  testWidgets(
    'NovelReaderPage exposes paged semantics and mounts nearby pages only',
    (tester) async {
      final repository = _FakeNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.pagedLtr,
        ),
        firstParagraphs: List<String>.generate(
          40,
          (index) => '语义分页段落 $index ${List<String>.filled(120, '正文').join()}',
        ),
      );
      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.byKey(const Key('novel-reader-paged-semantics')),
      );
      expect(semantics.label, contains('第 1 页'));
      final mountedPages = find
          .byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('novel-reader-paged-page-');
          })
          .evaluate()
          .length;
      expect(mountedPages, lessThan(6));
    },
  );

  testWidgets('NovelReaderPage vertical mode does not bind paged view', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: List<String>.generate(
        18,
        (index) => '滚动段落 $index ${List<String>.filled(70, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-paragraph-list')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('novel-reader-paged-page-view')), findsNothing);

    await tester.tapAt(const Offset(720, 300));
    await tester.pumpAndSettle();

    expect(repository.readingProgress?.pageIndex ?? 0, 0);
  });

  testWidgets('NovelReaderPage keeps logical first page in RTL mode', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedRtl,
      ),
      firstParagraphs: List<String>.generate(
        8,
        (index) => 'RTL 分页段落 $index ${List<String>.filled(48, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(
      find.byKey(const Key('novel-reader-paged-page-view')),
    );
    expect(pageView.reverse, isTrue);
    expect(find.textContaining('1 /'), findsOneWidget);
  });

  testWidgets('NovelReaderPage constrains wide content column', (tester) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        contentMaxWidth: 360,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    final width = tester
        .getSize(find.byKey(const Key('novel-reader-content-column')))
        .width;

    expect(width, lessThanOrEqualTo(360));
  });

  testWidgets('NovelReaderPage does not duplicate chapter title in body', (
    tester,
  ) async {
    final repository = _FakeNovelRepository();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-inline-chapter-title')),
      findsNothing,
    );
    expect(_readerText('第一段。'), findsOneWidget);
  });

  testWidgets('NovelReaderPage open thread uses novel detail source tid', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(),
        threadRepository: _FakeThreadRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-top-action-open-thread')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(ThreadDetailPage), findsOneWidget);
  });

  testWidgets('NovelReaderPage back button saves progress before pop', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: List<String>.generate(30, (index) => '第一章段落 $index'),
    );
    await tester.pumpWidget(
      LocalizedTestApp(
        home: ProviderScope(
          overrides: [
            novelRepositoryProvider.overrideWithValue(repository),
            novelReaderPreferencesRepositoryProvider.overrideWithValue(
              _FakeNovelReaderPreferencesRepository(repository),
            ),
            imageRequestHeaderBuilderProvider.overrideWithValue(
              const _StaticImageHeaderBuilder(),
            ),
            libraryStateRepositoryProvider.overrideWithValue(
              _MemoryLibraryStateRepository(),
            ),
          ],
          child: const NovelReaderPage(
            novelId: 'novel:49:100',
            initialEpisodeId: 'novel:49:100:5001',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('novel-reader-paragraph-list')),
      const Offset(0, -220),
    );
    await tester.pump();
    await _showReaderMenu(tester);

    await tester.tap(find.byKey(const Key('shared-reader-top-back-button')));
    await tester.pumpAndSettle();

    expect(repository.lastSavedOffset, greaterThan(0));
  });

  testWidgets('NovelReaderPage system pop saves progress before pop', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: List<String>.generate(30, (index) => '第一章段落 $index'),
    );
    await tester.pumpWidget(
      LocalizedTestApp(
        home: ProviderScope(
          overrides: [
            novelRepositoryProvider.overrideWithValue(repository),
            novelReaderPreferencesRepositoryProvider.overrideWithValue(
              _FakeNovelReaderPreferencesRepository(repository),
            ),
            imageRequestHeaderBuilderProvider.overrideWithValue(
              const _StaticImageHeaderBuilder(),
            ),
            libraryStateRepositoryProvider.overrideWithValue(
              _MemoryLibraryStateRepository(),
            ),
          ],
          child: const NovelReaderPage(
            novelId: 'novel:49:100',
            initialEpisodeId: 'novel:49:100:5001',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('novel-reader-paragraph-list')),
      const Offset(0, -220),
    );
    await tester.pump();

    final navigator = Navigator.of(
      tester.element(find.byType(NovelReaderPage)),
    );
    navigator.maybePop();
    await tester.pumpAndSettle();

    expect(repository.lastSavedOffset, greaterThan(0));
  });

  testWidgets('NovelReaderPage flushes progress when app goes inactive', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: List<String>.generate(30, (index) => '第一章段落 $index'),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('novel-reader-paragraph-list')),
      const Offset(0, -220),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    expect(repository.lastSavedOffset, greaterThan(0));
  });

  testWidgets('NovelReaderPage next chapter transition opens next episode', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-next-chapter-transition')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('novel-reader-next-chapter-button')));
    await tester.pumpAndSettle();

    expect(_readerText('第三段。'), findsOneWidget);
    expect(repository.readingProgress?.episodeId, 'novel:49:100:5002');
    expect(repository.readingProgress?.scrollOffset, 0);
    expect(repository.readingProgress?.progressPercent, 0);
  });

  testWidgets('NovelReaderPage turns chapters repeatedly by paged overscroll', (
    tester,
  ) async {
    // The gesture used to work exactly once per visit to the reader: the entry
    // request armed by the first turn was never retired, so it kept reporting a
    // turn as in flight forever.
    final repository = _FakeNovelRepository.threeEpisodes(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(_readerText('第一段。'), findsOneWidget);

    final pageView = find.byKey(const Key('novel-reader-paged-page-view'));
    await tester.drag(pageView, const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(_readerText('第三段。'), findsOneWidget);

    await tester.drag(pageView, const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(_readerText('第五段。'), findsOneWidget);
    expect(repository.readingProgress?.episodeId, 'novel:49:100:5003');
  });

  testWidgets('NovelReaderPage paged overscroll returns to the previous chapter', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
    );
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        initialEpisodeId: 'novel:49:100:5002',
      ),
    );
    await tester.pumpAndSettle();

    expect(_readerText('第三段。'), findsOneWidget);

    final pageView = find.byKey(const Key('novel-reader-paged-page-view'));
    await tester.drag(pageView, const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(_readerText('第一段。'), findsOneWidget);

    // And forward again from there, proving neither direction latches.
    await tester.drag(pageView, const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(_readerText('第三段。'), findsOneWidget);
  });

  testWidgets('NovelReaderPage hides next chapter transition on last episode', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        initialEpisodeId: 'novel:49:100:5003',
      ),
    );
    await tester.pumpAndSettle();

    expect(_readerText('第五段。'), findsOneWidget);
    await _showReaderMenu(tester);
    expect(find.byKey(const Key('shared-reader-prev-button')), findsOneWidget);
    expect(find.byKey(const Key('shared-reader-next-button')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shared-reader-prev-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shared-reader-next-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(const Key('novel-reader-next-chapter-transition')),
      findsNothing,
    );
  });

  testWidgets('NovelReaderPage opens thread links from reader document', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(
          firstRawHtml:
              '<p><a href="forum.php?mod=viewthread&amp;tid=200">跳转原帖</a></p>',
          firstParagraphs: const <String>['跳转原帖'],
        ),
        threadRepository: _FakeThreadRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final linkText = _readerText('跳转原帖');
    await tester.tapAt(tester.getTopLeft(linkText) + const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(ThreadDetailPage), findsOneWidget);
  });

  testWidgets('NovelReaderPage toggles episode bookmark', (tester) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-top-action-bookmark')),
    );
    await tester.pumpAndSettle();

    expect(
      repository.bookmarks.map((bookmark) => bookmark.bookmarkId),
      contains('episode-bookmark:novel:49:100:5001'),
    );
  });

  testWidgets('NovelReaderPage catalog shows bookmark badge', (tester) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    repository.bookmarks.add(
      NovelReaderBookmark(
        bookmarkId: 'episode-bookmark:novel:49:100:5001',
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
        anchor: const NovelReaderTextAnchor(episodeId: 'novel:49:100:5001'),
        title: '第1章',
        snippet: '章节书签',
        createdAt: DateTime(2026, 6, 8),
        updatedAt: DateTime(2026, 6, 8),
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-chapter-bookmark-novel:49:100:5001')),
      findsOneWidget,
    );
  });

  testWidgets('NovelReaderPage has no duplicate chapter cache action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildReaderApp(repository: _FakeNovelRepository()),
    );
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);

    expect(
      find.byKey(const Key('shared-reader-bottom-action-cache')),
      findsNothing,
    );
    expect(find.text('缓存'), findsNothing);
  });

  testWidgets('NovelReaderPage renders hydrated repository content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(
          firstRawHtml: '<h2>水合标题</h2><p>水合正文。</p>',
          firstParagraphs: const <String>['水合标题', '水合正文。'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_readerText('水合标题'), findsOneWidget);
    expect(_readerText('水合正文。'), findsOneWidget);
    expect(
      find.byKey(const Key('novel-reader-html-document-view')),
      findsOneWidget,
    );
  });

  testWidgets('NovelReaderPage error view can update the work', (tester) async {
    final repository = _FakeNovelRepository(
      contentsByEpisodeId: const <String, NovelChapterContent>{},
    );
    final updateService = _RecordingNovelChapterUpdateService();
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        chapterUpdateService: updateService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-error-view')), findsOneWidget);
    await tester.tap(find.byKey(const Key('novel-reader-error-update-work')));
    await tester.pumpAndSettle();

    expect(updateService.novelIds, <String>['novel:49:100']);
    expect(find.text('更新作品'), findsOneWidget);
  });

  testWidgets(
    'NovelReaderPage large document build delay still enters reader',
    (tester) async {
      final repository = _FakeNovelRepository(
        firstRawHtml: '<p>${List<String>.filled(15000, '文').join()}</p>',
        firstParagraphs: const <String>['大章节正文'],
      );
      final documentBuildService = _DelayedNovelReaderDocumentBuildService(
        const Duration(milliseconds: 120),
      );

      await tester.pumpWidget(
        _buildReaderApp(
          repository: repository,
          documentBuildService: documentBuildService,
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();

      expect(
        find.byKey(const Key('novel-reader-paragraph-list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('novel-reader-html-document-view')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'NovelReaderPage chapter sheet updates bookmark badge after late hydration',
    (tester) async {
      final repository = _FakeNovelRepository.threeEpisodes();
      final hydrationService =
          _ControlledNovelReaderSupplementalHydrationService();

      await tester.pumpWidget(
        _buildReaderApp(
          repository: repository,
          supplementalHydrationService: hydrationService,
        ),
      );
      await tester.pumpAndSettle();

      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-catalog')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key('novel-reader-chapter-bookmark-novel:49:100:5001'),
        ),
        findsNothing,
      );

      hydrationService.completeBookmarks(<NovelReaderBookmark>[
        NovelReaderBookmark(
          bookmarkId: 'episode-bookmark:novel:49:100:5001',
          novelId: 'novel:49:100',
          episodeId: 'novel:49:100:5001',
          anchor: const NovelReaderTextAnchor(episodeId: 'novel:49:100:5001'),
          title: '章节书签',
          snippet: '章节书签',
          createdAt: DateTime(2026, 6, 8),
          updatedAt: DateTime(2026, 6, 8),
        ),
      ]);
      hydrationService.completeNovelTitle('测试小说');
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key('novel-reader-chapter-bookmark-novel:49:100:5001'),
        ),
        findsOneWidget,
      );
    },
  );
}

Future<void> _showReaderMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(400, 300));
  await tester.pump(const Duration(milliseconds: 330));
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump();
}

Finder _readerText(String text) {
  return find.byWidgetPredicate((widget) {
    return widget is RichText && widget.text.toPlainText().contains(text);
  });
}

Widget _buildReaderApp({
  required _FakeNovelRepository repository,
  LibraryStateRepository? stateRepository,
  ThreadRepository? threadRepository,
  NovelReaderDocumentBuildService? documentBuildService,
  NovelReaderSupplementalHydrationService? supplementalHydrationService,
  NovelChapterUpdateService? chapterUpdateService,
  ThemeData? theme,
  String initialEpisodeId = 'novel:49:100:5001',
  Widget? home,
}) {
  return ProviderScope(
    overrides: [
      novelRepositoryProvider.overrideWithValue(repository),
      novelReaderPreferencesRepositoryProvider.overrideWithValue(
        _FakeNovelReaderPreferencesRepository(repository),
      ),
      novelChapterUpdateServiceProvider.overrideWithValue(
        chapterUpdateService ?? _RecordingNovelChapterUpdateService(),
      ),
      forumWebViewExternalLauncherProvider.overrideWithValue(
        _FakeForumWebViewExternalLauncher(),
      ),
      imageRequestHeaderBuilderProvider.overrideWithValue(
        const _StaticImageHeaderBuilder(),
      ),
      imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
      if (documentBuildService != null)
        novelReaderDocumentBuildServiceProvider.overrideWithValue(
          documentBuildService,
        ),
      if (supplementalHydrationService != null)
        novelReaderSupplementalHydrationServiceProvider.overrideWithValue(
          supplementalHydrationService,
        ),
      libraryStateRepositoryProvider.overrideWithValue(
        stateRepository ?? _MemoryLibraryStateRepository(),
      ),
      if (threadRepository != null)
        threadRepositoryProvider.overrideWithValue(threadRepository),
    ],
    child: LocalizedTestApp(
      theme: theme,
      home:
          home ??
          NovelReaderPage(
            novelId: 'novel:49:100',
            initialEpisodeId: initialEpisodeId,
          ),
    ),
  );
}

class _NovelReaderRoundTripHost extends StatelessWidget {
  const _NovelReaderRoundTripHost();

  @override
  Widget build(BuildContext context) {
    Future<void> open(NovelEpisodeOpenPolicy policy) {
      return Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NovelReaderPage(
            novelId: 'novel:49:100',
            initialEpisodeId: 'novel:49:100:5001',
            openPolicy: policy,
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          TextButton(
            key: const Key('open-novel-from-beginning'),
            onPressed: () => open(NovelEpisodeOpenPolicy.startAtBeginning),
            child: const Text('从头阅读'),
          ),
          TextButton(
            key: const Key('continue-novel-reading'),
            onPressed: () => open(NovelEpisodeOpenPolicy.resumeLastRead),
            child: const Text('继续阅读'),
          ),
        ],
      ),
    );
  }
}

class _RecordingNovelChapterUpdateService implements NovelChapterUpdateService {
  final List<String> novelIds = <String>[];

  @override
  Future<NovelChapterSyncResult> update(String novelId) async {
    novelIds.add(novelId);
    return NovelChapterSyncResult(
      mode: NovelChapterSyncMode.incremental,
      fetchedPages: 1,
      insertedCount: 0,
      updatedCount: 1,
      totalCount: 2,
      checkpoint: NovelChapterSyncCheckpoint(
        novelId: novelId,
        publisherId: '406769',
        lastCompletedAuthorPage: 1,
        lastSeenPid: '5002',
        completedAt: DateTime(2026, 7, 14),
      ),
    );
  }
}

class _FakeForumWebViewExternalLauncher
    implements ForumWebViewExternalLauncher {
  @override
  Future<bool> launch(Uri uri) async => true;
}

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{};
  }
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

class _FakeThreadRepository implements ThreadRepository {
  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
    Map<String, String> queryParameters = const <String, String>{},
  }) async {
    return ApiSuccess(
      ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: '测试小说',
        author: 'alice',
        replies: 0,
        views: 1,
        currentPage: page,
        perPage: 20,
        posts: const <ThreadPost>[],
      ),
    );
  }
}

class _MemoryLibraryStateRepository implements LibraryStateRepository {
  final Map<String, LibraryEpisodeState> _episodeStates =
      <String, LibraryEpisodeState>{};

  @override
  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  }) async {
    final old = _episodeStates[episodeId];
    _episodeStates[episodeId] = LibraryEpisodeState(
      moduleKey: moduleKey,
      episodeId: episodeId,
      workId: workId,
      isRead: isRead ?? old?.isRead ?? false,
      isDownloaded: isDownloaded ?? old?.isDownloaded ?? false,
      isBookmarked: isBookmarked ?? old?.isBookmarked ?? false,
      readAt: isRead == false ? null : readAt ?? old?.readAt,
      downloadedAt: isDownloaded == false
          ? null
          : downloadedAt ?? old?.downloadedAt,
    );
  }

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async {
    final state = _episodeStates[episodeId];
    return state?.moduleKey == moduleKey ? state : null;
  }

  @override
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  }) async {}

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return null;
  }

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return _episodeStates.values
        .where(
          (state) =>
              state.moduleKey == moduleKey &&
              state.workId == workId &&
              state.isDownloaded,
        )
        .length;
  }

  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}

  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {}

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 6, 8),
    );
  }

  @override
  Future<String> createTag({required String name}) async => 'tag';

  @override
  Future<List<LibraryTag>> getTags() async => const <LibraryTag>[];

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
  }) async {}

  @override
  Future<void> deleteTag({required String tagId}) async {}

  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return const <LibraryTag>[];
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return false;
  }
}

class _FakeNovelRepository implements NovelRepository {
  _FakeNovelRepository({
    List<String>? firstParagraphs,
    String? firstRawHtml,
    NovelReaderPreferences? preferences,
    List<NovelEpisodeItem>? episodes,
    Map<String, NovelChapterContent>? contentsByEpisodeId,
    this.readingProgress,
    this.chapterLoadDelay = Duration.zero,
    this.failedEpisodeIds = const <String>{},
  }) : episodes = episodes ?? _defaultEpisodes(),
       contentsByEpisodeId =
           contentsByEpisodeId ??
           _defaultContents(
             firstParagraphs: firstParagraphs,
             firstRawHtml: firstRawHtml,
           ),
       preferences = preferences ?? NovelReaderPreferences.defaults();

  factory _FakeNovelRepository.threeEpisodes({
    NovelReadingProgress? readingProgress,
    Duration chapterLoadDelay = Duration.zero,
    Set<String> failedEpisodeIds = const <String>{},
    NovelReaderPreferences? preferences,
  }) {
    return _FakeNovelRepository(
      preferences: preferences,
      episodes: _threeEpisodes(),
      contentsByEpisodeId: _contentsForParagraphs(const <String, List<String>>{
        'novel:49:100:5001': <String>['第一段。', '第二段。'],
        'novel:49:100:5002': <String>['第三段。', '第四段。'],
        'novel:49:100:5003': <String>['第五段。', '第六段。'],
      }),
      readingProgress: readingProgress,
      chapterLoadDelay: chapterLoadDelay,
      failedEpisodeIds: failedEpisodeIds,
    );
  }

  factory _FakeNovelRepository.manyEpisodes({
    required int count,
    required int currentIndex,
  }) {
    final episodes = List<NovelEpisodeItem>.generate(count, (index) {
      final number = index + 1;
      final pid = (5000 + number).toString();
      return NovelEpisodeItem(
        episodeId: 'novel:49:100:$pid',
        novelId: 'novel:49:100',
        sourceTid: '100',
        sourcePid: pid,
        sourcePage: 1,
        episodeTitle: '第$number章',
        orderIndex: index,
        datelineText: '2026-05-${number.toString().padLeft(2, '0')}',
      );
    });
    final contents = <String, NovelChapterContent>{
      for (final episode in episodes)
        episode.episodeId: _contentFromParagraphs(episode.episodeId, <String>[
          '${episode.episodeTitle}正文。',
        ]),
    };
    return _FakeNovelRepository(
      episodes: episodes,
      contentsByEpisodeId: contents,
      readingProgress: NovelReadingProgress(
        novelId: 'novel:49:100',
        episodeId: episodes[currentIndex].episodeId,
        scrollOffset: 0,
        updatedAt: DateTime(2026, 6, 1),
      ),
      chapterLoadDelay: Duration.zero,
      failedEpisodeIds: const <String>{},
    );
  }

  final List<NovelEpisodeItem> episodes;
  final Map<String, NovelChapterContent> contentsByEpisodeId;
  NovelReadingProgress? readingProgress;
  final Duration chapterLoadDelay;
  final Set<String> failedEpisodeIds;
  NovelReaderPreferences preferences;
  NovelReaderPreferences? latestPreferences;
  int upsertPreferencesCallCount = 0;
  double lastSavedOffset = 0;
  int refreshCount = 0;
  final savedProgressEpisodeIds = <String>[];
  final bookmarks = <NovelReaderBookmark>[];

  @override
  Future<String> createCategory({required String name}) async => 'default';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return <NovelShelfCategory>[
      NovelShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
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
  Future<NovelChapterContent?> getChapterContent({
    required String episodeId,
  }) async {
    if (chapterLoadDelay > Duration.zero) {
      await Future<void>.delayed(chapterLoadDelay);
    }
    if (failedEpisodeIds.contains(episodeId)) {
      throw StateError('章节内容不存在');
    }
    return contentsByEpisodeId[episodeId];
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return descending ? episodes.reversed.toList(growable: false) : episodes;
  }

  @override
  Future<List<NovelItem>> getShelfItems({
    String categoryId = 'default',
  }) async => const <NovelItem>[];

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<NovelReadingProgress?> getReadingProgress({
    required String novelId,
  }) async {
    return readingProgress;
  }

  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    refreshCount += 1;
    return NovelEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: episodes.length,
    );
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    int? pageCount,
    String? anchorNodeId,
    int anchorTextOffset = 0,
    String? paginationKey,
    double progressPercent = 0,
  }) async {
    savedProgressEpisodeIds.add(episodeId);
    lastSavedOffset = scrollOffset;
    readingProgress = NovelReadingProgress(
      novelId: novelId,
      episodeId: episodeId,
      scrollOffset: scrollOffset,
      updatedAt: DateTime(2026, 6, 8),
      flowMode: flowMode,
      pageIndex: pageIndex,
      pageCount: pageCount,
      anchorNodeId: anchorNodeId,
      anchorTextOffset: anchorTextOffset,
      paginationKey: paginationKey,
      progressPercent: progressPercent,
    );
  }

  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {}

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {
    bookmarks.removeWhere((item) => item.bookmarkId == bookmark.bookmarkId);
    bookmarks.add(bookmark);
  }

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    return bookmarks.where((bookmark) => bookmark.novelId == novelId).toList();
  }

  @override
  Future<void> removeReaderBookmark({required String bookmarkId}) async {
    bookmarks.removeWhere((bookmark) => bookmark.bookmarkId == bookmarkId);
  }

  @override
  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  }) async {
    bookmarks.removeWhere(
      (bookmark) => bookmark.bookmarkId == 'episode-bookmark:$episodeId',
    );
    if (!isBookmarked) {
      return;
    }
    final episode = episodes.firstWhere((item) => item.episodeId == episodeId);
    bookmarks.add(
      NovelReaderBookmark(
        bookmarkId: 'episode-bookmark:$episodeId',
        novelId: novelId,
        episodeId: episodeId,
        anchor: NovelReaderTextAnchor(episodeId: episodeId),
        title: episode.episodeTitle,
        snippet: '章节书签',
        createdAt: DateTime(2026, 6, 8),
        updatedAt: DateTime(2026, 6, 8),
      ),
    );
  }

  static String _rawHtmlFromParagraphs(List<String> paragraphs) {
    return paragraphs.map((paragraph) => '<p>$paragraph</p>').join();
  }

  static List<NovelEpisodeItem> _defaultEpisodes() {
    return _threeEpisodes().take(2).toList(growable: false);
  }

  static List<NovelEpisodeItem> _threeEpisodes() {
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

  static Map<String, NovelChapterContent> _defaultContents({
    List<String>? firstParagraphs,
    String? firstRawHtml,
  }) {
    final paragraphs = firstParagraphs ?? const <String>['第一段。', '第二段。'];
    final rawHtml = firstRawHtml ?? _rawHtmlFromParagraphs(paragraphs);
    return <String, NovelChapterContent>{
      'novel:49:100:5001': NovelChapterContent(
        episodeId: 'novel:49:100:5001',
        rawHtml: rawHtml,
        plainText: paragraphs.join('\n'),
        paragraphs: paragraphs,
      ),
      'novel:49:100:5002': const NovelChapterContent(
        episodeId: 'novel:49:100:5002',
        rawHtml: '<p>第三段。</p><p>第四段。</p>',
        plainText: '第三段。\n第四段。',
        paragraphs: <String>['第三段。', '第四段。'],
      ),
    };
  }

  static Map<String, NovelChapterContent> _contentsForParagraphs(
    Map<String, List<String>> source,
  ) {
    return <String, NovelChapterContent>{
      for (final entry in source.entries)
        entry.key: _contentFromParagraphs(entry.key, entry.value),
    };
  }

  static NovelChapterContent _contentFromParagraphs(
    String episodeId,
    List<String> paragraphs,
  ) {
    return NovelChapterContent(
      episodeId: episodeId,
      rawHtml: _rawHtmlFromParagraphs(paragraphs),
      plainText: paragraphs.join('\n'),
      paragraphs: paragraphs,
    );
  }
}

class _FakeNovelReaderPreferencesRepository
    implements NovelReaderPreferencesRepository {
  const _FakeNovelReaderPreferencesRepository(this.repository);

  final _FakeNovelRepository repository;

  @override
  Future<NovelReaderPreferences> load() async => repository.preferences;

  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    repository.upsertPreferencesCallCount += 1;
    repository.latestPreferences = preferences;
    repository.preferences = preferences;
  }
}

class _DelayedNovelReaderDocumentBuildService
    implements NovelReaderDocumentBuildService {
  _DelayedNovelReaderDocumentBuildService(this.delay);

  final Duration delay;

  @override
  Future<NovelReaderDocument> build(
    NovelReaderDocumentBuildRequest request, {
    TextConverter converter = const IdentityTextConverter(),
  }) async {
    await Future<void>.delayed(delay);
    return const DiscuzNovelReaderDocumentParser().parse(
      episodeId: request.episodeId,
      rawHtml: request.rawHtml,
      fallbackParagraphs: request.fallbackParagraphs,
    );
  }
}

class _ControlledNovelReaderSupplementalHydrationService
    implements NovelReaderSupplementalHydrationService {
  final Completer<List<NovelReaderBookmark>> _bookmarksCompleter =
      Completer<List<NovelReaderBookmark>>();
  final Completer<NovelItem?> _novelCompleter = Completer<NovelItem?>();

  @override
  Future<List<NovelReaderBookmark>> loadBookmarks({required String novelId}) {
    return _bookmarksCompleter.future;
  }

  @override
  Future<NovelItem?> loadNovel({required String novelId}) {
    return _novelCompleter.future;
  }

  void completeBookmarks(List<NovelReaderBookmark> value) {
    if (!_bookmarksCompleter.isCompleted) {
      _bookmarksCompleter.complete(value);
    }
  }

  void completeNovelTitle(String title) {
    if (!_novelCompleter.isCompleted) {
      _novelCompleter.complete(
        NovelItem(
          novelId: 'novel:49:100',
          sourceTid: '100',
          sourceFid: '49',
          title: title,
          updatedAt: DateTime(2026, 1, 1),
          episodeCount: 3,
        ),
      );
    }
  }
}
