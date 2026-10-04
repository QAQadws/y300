import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/library_shared/domain/models/reader_corner_dock_side.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_corner_dock.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/preferences/novel_chapter_interactions_dock_preferences_provider.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_episode_open_policy.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_interactions_dock_preferences_repository.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_update_service.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_document_view.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_supplemental_hydration_service.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/l10n/app_localizations.dart';

void main() {
  testWidgets('short paged chapter starts preparing during route entrance', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
    );
    late BuildContext hostContext;
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final route = PageRouteBuilder<void>(
      transitionDuration: const Duration(seconds: 1),
      pageBuilder: (_, _, _) => const NovelReaderPage(
        novelId: 'novel:49:100',
        initialEpisodeId: 'novel:49:100:5001',
      ),
    );
    unawaited(Navigator.of(hostContext).push(route));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.byKey(const Key('novel-reader-delayed-loading-indicator')),
        findsNothing,
      );
    }
    expect(route.animation!.status, AnimationStatus.forward);
    expect(
      find.byKey(const Key('novel-reader-paged-page-view')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-surface')),
      findsNothing,
    );
    await tester.pumpAndSettle();
  });

  for (final (fraction, chunked) in [
    (0.5, false),
    (1.0, false),
    (0.5, true),
    (1.0, true),
  ]) {
    testWidgets(
      'vertical resume $fraction chunks=$chunked reveals only its settled position',
      (tester) async {
        final repository = _FakeNovelRepository(
          firstRawHtml: chunked
              ? List.generate(
                  400,
                  (index) => 'fixture-$index ${'正文保留🙂' * 12}<br><br>',
                ).join()
              : null,
          firstParagraphs: List.generate(
            80,
            (index) => 'fixture $index ${'正文' * (index < 10 ? 2 : 20)}',
          ),
          readingProgress: NovelReadingProgress(
            novelId: 'novel:49:100',
            episodeId: 'novel:49:100:5001',
            scrollOffset: 10,
            progressPercent: fraction,
            updatedAt: DateTime(2026),
          ),
        );
        await tester.pumpWidget(_buildReaderApp(repository: repository));
        double? firstVisibleOffset;
        var visibleFrames = 0;
        for (var frame = 0; frame < 300 && visibleFrames < 20; frame++) {
          // The semantic document can be built on a real worker isolate.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          final finder = find.descendant(
            of: find.byKey(const Key('novel-reader-paragraph-list')),
            matching: find.byType(Scrollable),
          );
          if (finder.evaluate().isEmpty ||
              find
                  .byKey(const Key('novel-reader-delayed-loading-surface'))
                  .evaluate()
                  .isNotEmpty) {
            continue;
          }
          final position = tester.state<ScrollableState>(finder).position;
          expect(
            position.pixels,
            closeTo(position.maxScrollExtent * fraction, 1),
          );
          expect(position.isScrollingNotifier.value, isFalse);
          firstVisibleOffset ??= position.pixels;
          expect(position.pixels, closeTo(firstVisibleOffset, 0.01));
          visibleFrames++;
        }
        expect(firstVisibleOffset, isNotNull);
        expect(firstVisibleOffset, greaterThan(0));
        expect(tester.takeException(), isNull);
      },
    );
  }

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
      final expectedOffset = position.maxScrollExtent * 0.25;
      expect(position.pixels, closeTo(expectedOffset, 0.01));
      // The corrected viewport no longer waits for an entrance animation;
      // persistence retains its independent debounce, not a rendering delay.
      await tester.pump(const Duration(seconds: 1));
      expect(
        repository.readingProgress?.scrollOffset,
        closeTo(expectedOffset, 0.01),
      );
    },
  );

  testWidgets(
    'old vertical callbacks cannot project into a rebuilt provider before paint',
    (tester) async {
      final repository = _FakeNovelRepository(
        firstParagraphs: List.generate(
          80,
          (index) => '恢复隔离正文 $index ${'正文' * 12}',
        ),
      );
      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await _pumpVerticalReaderReady(tester);
      final oldHtml = tester.widget<NovelReaderHtmlDocumentView>(
        find.byType(NovelReaderHtmlDocumentView),
      );
      final oldPosition = _verticalPosition(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NovelReaderPage)),
        listen: false,
      );
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      repository.readingProgress = NovelReadingProgress(
        novelId: args.novelId,
        episodeId: args.episodeId,
        scrollOffset: 444,
        progressPercent: 0.4,
        updatedAt: DateTime(2026),
      );
      container.invalidate(provider);
      final rebuilt = (await tester.runAsync(
        () => container.read(provider.future),
      ))!;

      // Provider state has changed, while the old viewport has not rebuilt yet.
      oldPosition.jumpTo(60);
      oldHtml.onContentReady?.call();
      oldHtml.onContentTerminal?.call();
      expect(
        container.read(provider).value!.progressSnapshot,
        rebuilt.progressSnapshot,
      );
      expect(
        container.read(provider).value!.readingProgress,
        rebuilt.readingProgress,
      );

      await _pumpVerticalReaderReady(tester);
      final position = _verticalPosition(tester);
      expect(position.pixels, closeTo(position.maxScrollExtent * 0.4, 1));
      expect(
        find.byKey(const Key('novel-reader-delayed-loading-surface')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed vertical chapter switch restores the visible offset and resumes progress',
    (tester) async {
      final repository = _FakeNovelRepository.threeEpisodes(
        firstParagraphs: List.generate(
          80,
          (index) => '失败恢复正文 $index ${'正文' * 12}',
        ),
        failedEpisodeIds: const {'novel:49:100:5002'},
        chapterLoadDelay: const Duration(milliseconds: 120),
      );
      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await _pumpVerticalReaderReady(tester);
      final failure = AppLocalizations.of(
        tester.element(find.byType(NovelReaderPage)),
      ).novelChapterSwitchFailed;
      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      final before = _verticalPosition(tester).pixels;
      expect(before, greaterThan(0));
      repository.savedProgressOffsets.clear();

      await _showReaderMenu(tester);
      await tester.tap(find.byKey(const Key('shared-reader-next-button')));
      await tester.pumpAndSettle();
      expect(_verticalPosition(tester).pixels, closeTo(before, 0.01));
      expect(find.text(failure), findsOneWidget);
      expect(
        find.byKey(const Key('novel-reader-delayed-loading-surface')),
        findsNothing,
      );
      expect(repository.savedProgressOffsets, everyElement(greaterThan(0)));

      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      final after = _verticalPosition(tester).pixels;
      expect(after, greaterThan(before));
      expect(repository.readingProgress?.scrollOffset, closeTo(after, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'returning to the same chapter does not revive its old ready callback',
    (tester) async {
      final repository = _FakeNovelRepository.threeEpisodes(
        firstParagraphs: List.generate(
          80,
          (index) => '往返隔离正文 $index ${'正文' * 12}',
        ),
      );
      final committer = _ControlledPageProgressCommitter(
        repository,
        forwardScheduledCommits: true,
      );
      await tester.pumpWidget(
        _buildReaderApp(repository: repository, progressCommitter: committer),
      );
      await _pumpVerticalReaderReady(tester);
      await tester.drag(
        find.byKey(const Key('novel-reader-paragraph-list')),
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      expect(_verticalPosition(tester).pixels, greaterThan(0));
      expect(repository.readingProgress?.scrollOffset, greaterThan(0));
      final oldHtml = tester.widget<NovelReaderHtmlDocumentView>(
        find.byType(NovelReaderHtmlDocumentView),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NovelReaderPage)),
        listen: false,
      );
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final controller = container.read(provider.notifier);
      expect(
        await tester.runAsync(
          () => controller.openEpisodeFromCatalog('novel:49:100:5002'),
        ),
        isTrue,
      );
      expect(
        await tester.runAsync(
          () => controller.openEpisodeFromCatalog('novel:49:100:5001'),
        ),
        isTrue,
      );
      oldHtml.onContentReady?.call();
      oldHtml.onContentTerminal?.call();
      expect(committer.flushes, isEmpty);

      await _pumpVerticalReaderReady(tester);
      for (final flush in committer.flushes) {
        flush.complete();
      }
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      expect(_verticalPosition(tester).pixels, closeTo(0, 0.01));
      expect(container.read(provider).value!.progressSnapshot.scrollOffset, 0);
      expect(repository.readingProgress?.scrollOffset, 0);
      expect(
        container.read(provider).value!.currentEpisode.episodeId,
        'novel:49:100:5001',
      );
      expect(
        find.byKey(const Key('novel-reader-delayed-loading-surface')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late pre-switch flush cannot advance a different chapter', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    final committer = _ControlledPageProgressCommitter(repository);
    await tester.pumpWidget(
      _buildReaderApp(repository: repository, progressCommitter: committer),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovelReaderPage)),
      listen: false,
    );
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-next-button')));
    await tester.pump();
    expect(committer.flushes, hasLength(1));

    expect(
      await container
          .read(provider.notifier)
          .openEpisodeFromCatalog('novel:49:100:5002'),
      isTrue,
    );
    await tester.pumpAndSettle();
    committer.flushes.first.complete();
    await tester.pumpAndSettle();
    for (final flush in committer.flushes) {
      flush.complete();
    }
    await tester.pumpAndSettle();

    expect(
      container.read(provider).value!.currentEpisode.episodeId,
      'novel:49:100:5002',
    );
    expect(
      repository.chapterLoadEpisodeIds,
      isNot(contains('novel:49:100:5003')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disposed page does not switch after its progress flush completes',
    (tester) async {
      final repository = _FakeNovelRepository.threeEpisodes();
      final committer = _ControlledPageProgressCommitter(repository);
      await tester.pumpWidget(
        _buildReaderApp(repository: repository, progressCommitter: committer),
      );
      await tester.pumpAndSettle();
      await _showReaderMenu(tester);
      await tester.tap(find.byKey(const Key('shared-reader-next-button')));
      await tester.pump();
      expect(committer.flushes, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      committer.flushes.first.complete();
      await tester.pumpAndSettle();
      expect(
        repository.chapterLoadEpisodeIds,
        isNot(contains('novel:49:100:5002')),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late failed chapter switch stays silent on a newer chapter', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes(
      failedEpisodeIds: const {'novel:49:100:5002'},
    );
    final chapterGate = Completer<void>();
    repository.chapterLoadGates['novel:49:100:5002'] = chapterGate;
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NovelReaderPage));
    final failure = AppLocalizations.of(context).novelChapterSwitchFailed;
    final container = ProviderScope.containerOf(context, listen: false);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-next-button')));
    await tester.pump();
    await tester.pump();
    expect(repository.chapterLoadEpisodeIds, contains('novel:49:100:5002'));

    expect(
      await container
          .read(provider.notifier)
          .openEpisodeFromCatalog('novel:49:100:5003'),
      isTrue,
    );
    await tester.pumpAndSettle();
    chapterGate.complete();
    await tester.pumpAndSettle();
    expect(
      container.read(provider).value!.currentEpisode.episodeId,
      'novel:49:100:5003',
    );
    expect(find.text(failure), findsNothing);
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-surface')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('old vertical seek completion cannot unlock a newer seek', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: List.generate(
        80,
        (index) => '定位隔离正文 $index ${'正文' * 12}',
      ),
    );
    final committer = _ControlledPageProgressCommitter(repository);
    await tester.pumpWidget(
      _buildReaderApp(repository: repository, progressCommitter: committer),
    );
    await _pumpVerticalReaderReady(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovelReaderPage)),
      listen: false,
    );
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    await _showReaderMenu(tester);
    tester
        .widget<Slider>(find.byKey(const Key('shared-reader-progress-slider')))
        .onChangeEnd!(0.2);
    await tester.pump();
    expect(committer.flushes, hasLength(1));

    container.invalidate(provider);
    await tester.runAsync(() => container.read(provider.future));
    await _pumpVerticalReaderReady(tester);
    await _showReaderMenu(tester);
    tester
        .widget<Slider>(find.byKey(const Key('shared-reader-progress-slider')))
        .onChangeEnd!(0.7);
    await tester.pump();
    expect(committer.flushes, hasLength(2));
    committer.flushes.first.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AbsorbPointer>(
            find
                .ancestor(
                  of: find.byKey(const Key('shared-reader-progress-slider')),
                  matching: find.byType(AbsorbPointer),
                )
                .first,
          )
          .absorbing,
      isTrue,
    );
    expect(
      container.read(provider).value!.progressSnapshot.progressPercent,
      closeTo(0.7, 0.01),
    );

    committer.flushes.last.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AbsorbPointer>(
            find
                .ancestor(
                  of: find.byKey(const Key('shared-reader-progress-slider')),
                  matching: find.byType(AbsorbPointer),
                )
                .first,
          )
          .absorbing,
      isFalse,
    );
    expect(repository.readingProgress?.progressPercent, closeTo(0.7, 0.01));
    expect(tester.takeException(), isNull);
  });

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
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-surface')),
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

  testWidgets('NovelReaderPage chapter loading uses one neutral indicator', (
    tester,
  ) async {
    final theme = AppTheme.dark();
    final repository = _FakeNovelRepository.threeEpisodes(
      chapterLoadDelay: const Duration(milliseconds: 420),
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

    expect(find.byKey(const Key('novel-reader-transition-mask')), findsNothing);
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsOneWidget,
    );
    final surface = tester.widget<ColoredBox>(
      find.byKey(const Key('novel-reader-delayed-loading-surface')),
    );
    expect(surface.color, theme.scaffoldBackgroundColor);

    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsNothing,
    );
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

  testWidgets('NovelReaderPage follows application family and brightness', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.vertical,
      ),
      firstParagraphs: List<String>.generate(
        30,
        (index) => '主题同步阅读位置段落 $index',
      ),
    );
    final moonWhite = AppTheme.build(
      family: AppThemeFamily.moonWhite,
      brightness: Brightness.light,
    );
    final themeNotifier = ValueNotifier<ThemeData>(moonWhite);
    addTearDown(themeNotifier.dispose);
    await tester.pumpWidget(
      _buildReaderApp(repository: repository, themeListenable: themeNotifier),
    );
    await tester.pumpAndSettle();

    var background = tester.widget<ColoredBox>(
      find.byKey(const Key('novel-reader-background')),
    );
    expect(background.color, moonWhite.scaffoldBackgroundColor);
    final readerList = find.byKey(const Key('novel-reader-paragraph-list'));
    await tester.drag(readerList, const Offset(0, -160));
    await tester.pumpAndSettle();
    final offsetBeforeThemeChange = tester
        .state<ScrollableState>(
          find.descendant(of: readerList, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;

    final plumPurple = AppTheme.build(
      family: AppThemeFamily.plumPurple,
      brightness: Brightness.dark,
    );
    themeNotifier.value = plumPurple;
    await tester.pumpAndSettle();

    background = tester.widget<ColoredBox>(
      find.byKey(const Key('novel-reader-background')),
    );
    expect(background.color, plumPurple.scaffoldBackgroundColor);
    final offsetAfterThemeChange = tester
        .state<ScrollableState>(
          find.descendant(of: readerList, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(offsetAfterThemeChange, closeTo(offsetBeforeThemeChange, 0.01));
  });

  testWidgets(
    'NovelReaderPage chapter switch failure reveals old content and shows snackbar',
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
        findsNothing,
      );
      expect(_readerText('第一段。'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 140));
      await tester.pumpAndSettle();

      expect(_readerText('第一段。'), findsOneWidget);
      expect(_readerText('第三段。'), findsNothing);
      expect(find.text('章节切换失败，已保留当前章节'), findsOneWidget);
      expect(
        find.byKey(const Key('novel-reader-delayed-loading-indicator')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'NovelReaderPage display sheet is half height and applies theme live',
    (tester) async {
      final repository = _FakeNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.vertical,
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
      expect(find.byKey(const Key('novel-theme-follow-app')), findsOneWidget);
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
    const themeKeys = <Key>[
      Key('novel-theme-follow-app'),
      Key('novel-theme-light'),
      Key('novel-theme-sepia'),
      Key('novel-theme-dark'),
    ];
    final widgets = tester.allWidgets.toList(growable: false);
    final optionIndices = themeKeys
        .map((key) => widgets.indexWhere((widget) => widget.key == key))
        .toList(growable: false);
    expect(optionIndices.every((index) => index >= 0), isTrue);
    expect(optionIndices, orderedEquals(optionIndices.toList()..sort()));
    for (final key in themeKeys) {
      final chip = tester.widget<ChoiceChip>(
        find.descendant(of: find.byKey(key), matching: find.byType(ChoiceChip)),
      );
      expect(chip.showCheckmark, isFalse);
      expect(chip.selected, key == const Key('novel-theme-follow-app'));
    }
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
          flowMode: NovelReaderFlowMode.vertical,
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

  testWidgets('dismissing display settings flushes before the save debounce', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.vertical,
        themePreset: NovelReaderThemePreset.light,
      ),
    );
    final preferencesRepository = _ControlledPagePreferencesRepository(
      repository,
    );
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        preferencesRepository: preferencesRepository,
      ),
    );
    await tester.pumpAndSettle();
    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-display')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('novel-theme-sepia')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-theme-sepia')));
    await tester.pump();
    expect(preferencesRepository.saves, isEmpty);

    await tester.tapAt(const Offset(24, 24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(
      find.byKey(const Key('novel-reader-display-settings-sheet')),
      findsNothing,
    );
    expect(preferencesRepository.saves, hasLength(1));
    expect(repository.latestPreferences, isNull);
    preferencesRepository.saves.single.complete();
    await tester.pumpAndSettle();
    expect(
      repository.latestPreferences?.themePreset,
      NovelReaderThemePreset.sepia,
    );
    expect(repository.upsertPreferencesCallCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a failed active save after dismissal rolls back and reports localized error',
    (tester) async {
      final repository = _FakeNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.vertical,
          themePreset: NovelReaderThemePreset.light,
        ),
      );
      final preferencesRepository = _ControlledPagePreferencesRepository(
        repository,
      );
      await tester.pumpWidget(
        _buildReaderApp(
          repository: repository,
          preferencesRepository: preferencesRepository,
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(NovelReaderPage));
      final container = ProviderScope.containerOf(context, listen: false);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      final initial = container.read(provider).value!;
      final failureText = AppLocalizations.of(
        context,
      ).novelSaveDisplaySettingsFailed;
      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('novel-theme-sepia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-theme-sepia')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(preferencesRepository.saves, hasLength(1));
      await tester.tapAt(const Offset(24, 24));
      await tester.pumpAndSettle();
      expect(preferencesRepository.saves, hasLength(1));
      preferencesRepository.saves.single.fail();
      await tester.pumpAndSettle();

      final state = container.read(provider).value!;
      expect(state.preferences, initial.persistedPreferences);
      expect(state.persistedPreferences, initial.persistedPreferences);
      expect(state.progressSnapshot, initial.progressSnapshot);
      expect(find.text(failureText), findsOneWidget);
      expect(repository.latestPreferences, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reader rebuild retires the old sheet preview and save timers', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.vertical,
        themePreset: NovelReaderThemePreset.light,
      ),
    );
    final preferencesRepository = _ControlledPagePreferencesRepository(
      repository,
    );
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        preferencesRepository: preferencesRepository,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovelReaderPage)),
      listen: false,
    );
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-display')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('novel-theme-sepia')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-theme-sepia')));
    await tester.tap(find.byKey(const Key('novel-theme-dark')));
    container.invalidate(provider);
    final rebuilt = await container.read(provider.future);
    final nextPreview = rebuilt.preferences.copyWith(fontSize: 24);
    container.read(provider.notifier).previewPreferences(nextPreview);
    await tester.pump(const Duration(milliseconds: 600));
    expect(preferencesRepository.saves, isEmpty);
    expect(container.read(provider).value!.preferences, nextPreview);

    // The sheet still holds callbacks from the retired coordinator.
    await tester.tap(find.byKey(const Key('novel-theme-light')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(preferencesRepository.saves, isEmpty);
    expect(container.read(provider).value!.preferences, nextPreview);
    await tester.tapAt(const Offset(24, 24));
    await tester.pumpAndSettle();
    expect(preferencesRepository.saves, isEmpty);
    expect(
      container.read(provider).value!.persistedPreferences,
      rebuilt.persistedPreferences,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reader rebuild isolates a late save failure from the new preview',
    (tester) async {
      final repository = _FakeNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.vertical,
          themePreset: NovelReaderThemePreset.light,
        ),
      );
      final preferencesRepository = _ControlledPagePreferencesRepository(
        repository,
      );
      await tester.pumpWidget(
        _buildReaderApp(
          repository: repository,
          preferencesRepository: preferencesRepository,
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(NovelReaderPage));
      final failureText = AppLocalizations.of(
        context,
      ).novelSaveDisplaySettingsFailed;
      final container = ProviderScope.containerOf(context, listen: false);
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('novel-theme-sepia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-theme-sepia')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(preferencesRepository.saves, hasLength(1));
      container.invalidate(provider);
      final rebuilt = await container.read(provider.future);
      final nextPreview = rebuilt.preferences.copyWith(fontSize: 24);
      container.read(provider.notifier).previewPreferences(nextPreview);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(24, 24));
      await tester.pumpAndSettle();
      preferencesRepository.saves.single.fail();
      await tester.pumpAndSettle();

      final state = container.read(provider).value!;
      expect(state.preferences, nextPreview);
      expect(state.persistedPreferences, rebuilt.persistedPreferences);
      expect(state.progressSnapshot, rebuilt.progressSnapshot);
      expect(preferencesRepository.saves, hasLength(1));
      expect(find.text(failureText), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'latest baseline choice survives a successful save from the retired reader',
    (tester) async {
      final repository = _FakeNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.vertical,
          themePreset: NovelReaderThemePreset.light,
        ),
      );
      final original = repository.preferences;
      final preferencesRepository = _ControlledPagePreferencesRepository(
        repository,
      );
      await tester.pumpWidget(
        _buildReaderApp(
          repository: repository,
          preferencesRepository: preferencesRepository,
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NovelReaderPage)),
        listen: false,
      );
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final provider = novelReaderControllerProvider(args);
      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('novel-theme-sepia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-theme-sepia')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(preferencesRepository.saves, hasLength(1));
      container.invalidate(provider);
      final rebuilt = await container.read(provider.future);
      expect(rebuilt.persistedPreferences, original);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(24, 24));
      await tester.pumpAndSettle();

      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('novel-theme-dark')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-theme-dark')));
      await tester.tap(find.byKey(const Key('novel-theme-light')));
      await tester.pump();
      await tester.tapAt(const Offset(24, 24));
      await tester.pumpAndSettle();
      expect(preferencesRepository.saves, hasLength(1));

      preferencesRepository.saves.first.complete();
      await tester.pumpAndSettle();
      expect(preferencesRepository.saves, hasLength(2));
      expect(repository.preferences.themePreset, NovelReaderThemePreset.sepia);
      preferencesRepository.saves.last.complete();
      await tester.pumpAndSettle();
      expect(repository.preferences, original);
      expect(container.read(provider).value!.preferences, original);
      expect(container.read(provider).value!.persistedPreferences, original);
      expect(repository.upsertPreferencesCallCount, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('NovelReaderPage renders the paged LTR default', (tester) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults(),
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

  testWidgets(
    'phase 0 baseline: automatic surface fallback persists vertical mode '
    '(stage 2 flips this contract)',
    (tester) async {
      final repository = _FakeNovelRepository(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.pagedLtr,
        ),
      );
      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await tester.pumpAndSettle();

      final surface = tester.widget<NovelReaderHtmlPagedSurface>(
        find.byType(NovelReaderHtmlPagedSurface),
      );
      final savesBeforeFallback = repository.upsertPreferencesCallCount;
      expect(repository.preferences.flowMode, NovelReaderFlowMode.pagedLtr);

      // Surface timer tests cover automatic delivery; this exercises the actual
      // page callback through its display coordinator and preferences repository.
      surface.onFallbackToVertical!();
      await tester.pumpAndSettle();

      expect(repository.upsertPreferencesCallCount, savesBeforeFallback + 1);
      expect(
        repository.latestPreferences?.flowMode,
        NovelReaderFlowMode.vertical,
      );
      expect(repository.preferences.flowMode, NovelReaderFlowMode.vertical);
      expect(
        find.byKey(const Key('novel-reader-html-document-view')),
        findsOneWidget,
      );
      expect(find.byType(NovelReaderHtmlPagedSurface), findsNothing);
    },
  );

  testWidgets(
    'phase 0 baseline: retired paged fallback cannot save another chapter mode',
    (tester) async {
      final repository = _FakeNovelRepository.threeEpisodes(
        preferences: NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.pagedLtr,
        ),
      );
      await tester.pumpWidget(_buildReaderApp(repository: repository));
      await tester.pumpAndSettle();
      final oldSurface = tester.widget<NovelReaderHtmlPagedSurface>(
        find.byType(NovelReaderHtmlPagedSurface),
      );
      final oldFallback = oldSurface.onFallbackToVertical!;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NovelReaderPage)),
        listen: false,
      );
      const args = NovelReaderArgs(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
      );
      final controller = container.read(
        novelReaderControllerProvider(args).notifier,
      );
      expect(
        await tester.runAsync(
          () => controller.openEpisodeFromCatalog('novel:49:100:5002'),
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      final currentSurface = tester.widget<NovelReaderHtmlPagedSurface>(
        find.byType(NovelReaderHtmlPagedSurface),
      );
      expect(currentSurface.episode.episodeId, 'novel:49:100:5002');
      final savesBeforeLateCallback = repository.upsertPreferencesCallCount;

      oldFallback();
      await tester.pumpAndSettle();

      expect(repository.upsertPreferencesCallCount, savesBeforeLateCallback);
      expect(repository.preferences.flowMode, NovelReaderFlowMode.pagedLtr);
      expect(
        tester
            .widget<NovelReaderHtmlPagedSurface>(
              find.byType(NovelReaderHtmlPagedSurface),
            )
            .episode
            .episodeId,
        'novel:49:100:5002',
      );
    },
  );

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

  testWidgets('NovelReaderPage turns paged LTR content from side taps', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
      firstParagraphs: List<String>.generate(
        36,
        (index) => '点击翻页段落 $index ${List<String>.filled(120, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 /'), findsOneWidget);
    await tester.tapAt(const Offset(720, 300));
    await tester.pump(
      ReaderPagedTurnMotion.tapConfirmationDelay -
          const Duration(milliseconds: 1),
    );
    expect(find.textContaining('1 /'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(ReaderPagedTurnMotion.animationDuration);
    await tester.pumpAndSettle();
    expect(find.textContaining('2 /'), findsOneWidget);

    await _tapPagedReaderZone(tester, const Offset(80, 300));
    expect(find.textContaining('1 /'), findsOneWidget);
  });

  testWidgets('NovelReaderPage reverses side tap mapping in paged RTL', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedRtl,
      ),
      firstParagraphs: List<String>.generate(
        36,
        (index) => 'RTL 点击段落 $index ${List<String>.filled(120, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _tapPagedReaderZone(tester, const Offset(80, 300));
    expect(find.textContaining('2 /'), findsOneWidget);

    await _tapPagedReaderZone(tester, const Offset(720, 300));
    expect(find.textContaining('1 /'), findsOneWidget);
  });

  testWidgets('NovelReaderPage center tap still toggles paged chrome only', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
      firstParagraphs: List<String>.generate(
        20,
        (index) => '菜单段落 $index ${List<String>.filled(80, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);

    final topGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(topGate.ignoring, isFalse);
    expect(find.textContaining('1 /'), findsOneWidget);
  });

  testWidgets('NovelReaderPage side taps continue across chapter boundaries', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(_readerText('第一段。'), findsOneWidget);
    await _tapPagedReaderZone(tester, const Offset(720, 300));
    expect(_readerText('第三段。'), findsOneWidget);

    await _tapPagedReaderZone(tester, const Offset(80, 300));
    expect(_readerText('第一段。'), findsOneWidget);
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
        flowMode: NovelReaderFlowMode.vertical,
        contentMaxWidth: 360,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    final padding = tester
        .widget<SliverPadding>(
          find.byKey(const Key('novel-reader-content-column')),
        )
        .padding
        .resolve(TextDirection.ltr);
    final width =
        tester
            .getSize(find.byKey(const Key('novel-reader-paragraph-list')))
            .width -
        padding.horizontal;

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
    final openThread = find.byKey(
      const Key('shared-reader-top-action-open-thread'),
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-open-thread')),
      findsNothing,
    );
    await tester.tap(openThread);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(ThreadDetailPage), findsOneWidget);
  });

  testWidgets('vertical chapter action opens body end and preserves position', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: List.generate(40, (index) => '第 $index 段正文。'),
    );
    final locator = _ReaderPostLocator(tid: '100');
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        threadRepository: _FakeThreadRepository(targetPid: '5001'),
        threadPostLocator: locator,
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byKey(const Key('novel-reader-paragraph-list')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    final before = position.pixels;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final action = find.byKey(
      const Key('novel-reader-chapter-interactions-button'),
    );
    expect(
      tester.widget<ReaderCornerDock>(find.byType(ReaderCornerDock)).visible,
      isTrue,
    );
    expect(action, findsOneWidget);
    final atAction = position.pixels;
    expect(atAction, greaterThanOrEqualTo(before));
    await tester.tap(action);
    await tester.pumpAndSettle();
    final detail = tester.widget<ThreadDetailPage>(
      find.byType(ThreadDetailPage),
    );
    expect(
      (detail.tid, detail.targetPid, detail.landing),
      ('100', '5001', ThreadPostLanding.bodyEnd),
    );
    expect(locator.calls, 1);
    Navigator.of(tester.element(find.byType(ThreadDetailPage))).pop();
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(atAction, 0.01));
  });

  testWidgets('paged final-page action returns to the same page', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
    );
    final locator = _ReaderPostLocator(tid: '100');
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        threadRepository: _FakeThreadRepository(targetPid: '5001'),
        threadPostLocator: locator,
      ),
    );
    await tester.pumpAndSettle();
    final indicator = find.byKey(const Key('novel-reader-page-indicator-text'));
    final before = tester.widget<Text>(indicator).data;
    final action = find.byKey(
      const Key('novel-reader-chapter-interactions-button'),
    );
    expect(action, findsOneWidget);
    expect(
      tester.getRect(action).bottom,
      lessThan(tester.getRect(indicator).top),
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    final detail = tester.widget<ThreadDetailPage>(
      find.byType(ThreadDetailPage),
    );
    expect(
      (detail.tid, detail.targetPid, detail.landing),
      ('100', '5001', ThreadPostLanding.bodyEnd),
    );
    Navigator.of(tester.element(find.byType(ThreadDetailPage))).pop();
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(indicator).data, before);
    expect(locator.calls, 1);
  });

  testWidgets('display switch hides only the dock without rebuilding pages', (
    tester,
  ) async {
    final dockRepository = _FakeNovelChapterDockRepository();
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.pagedLtr,
          ),
        ),
        dockRepository: dockRepository,
      ),
    );
    await tester.pumpAndSettle();
    const buttonKey = Key('novel-reader-chapter-interactions-button');
    expect(find.byKey(buttonKey), findsOneWidget);
    final page = tester.element(
      find.byKey(const Key('novel-reader-paged-page-session')),
    );
    final indicator = tester
        .widget<Text>(find.byKey(const Key('novel-reader-page-indicator-text')))
        .data;

    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-display')),
    );
    await tester.pumpAndSettle();
    const switchKey = Key('novel-reader-chapter-interactions-dock-switch');
    await tester.ensureVisible(find.byKey(switchKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(switchKey));
    await tester.pumpAndSettle();
    expect(dockRepository.current.enabled, isFalse);
    Navigator.of(
      tester.element(
        find.byKey(const Key('novel-reader-display-settings-sheet')),
      ),
    ).pop();
    await tester.pumpAndSettle();

    expect(find.byKey(buttonKey), findsNothing);
    expect(
      tester.element(find.byKey(const Key('novel-reader-paged-page-session'))),
      same(page),
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('novel-reader-page-indicator-text')),
          )
          .data,
      indicator,
    );
    await _showReaderMenu(tester);
    expect(
      find.byKey(const Key('shared-reader-bottom-action-chapter-interactions')),
      findsOneWidget,
    );
  });

  testWidgets('novel dock long press snaps left without changing thread side', (
    tester,
  ) async {
    final dockRepository = _FakeNovelChapterDockRepository();
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.pagedLtr,
          ),
        ),
        dockRepository: dockRepository,
      ),
    );
    await tester.pumpAndSettle();
    final action = find.byKey(
      const Key('novel-reader-chapter-interactions-button'),
    );
    final initial = tester.getCenter(action);
    final gesture = await tester.startGesture(initial);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(-650, -50));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dockRepository.current.side, ReaderCornerDockSide.left);
    expect(tester.getCenter(action).dx, lessThan(initial.dx));
  });

  testWidgets('failed novel dock move restores the saved side', (tester) async {
    final dockRepository = _FakeNovelChapterDockRepository(failSave: true);
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(
          preferences: NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.pagedLtr,
          ),
        ),
        dockRepository: dockRepository,
      ),
    );
    await tester.pumpAndSettle();
    final action = find.byKey(
      const Key('novel-reader-chapter-interactions-button'),
    );
    final initial = tester.getCenter(action);
    final gesture = await tester.startGesture(initial);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(-650, -50));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dockRepository.current.side, ReaderCornerDockSide.right);
    expect(tester.getCenter(action).dx, initial.dx);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
    'vertical dock appears only within three quarters of a viewport',
    (tester) async {
      await tester.pumpWidget(
        _buildReaderApp(
          repository: _FakeNovelRepository(
            firstParagraphs: List.generate(40, (i) => '第 $i 段正文。'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find.descendant(
        of: find.byKey(const Key('novel-reader-paragraph-list')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      const buttonKey = Key('novel-reader-chapter-interactions-button');
      expect(find.byKey(buttonKey), findsNothing);
      position.jumpTo(
        position.maxScrollExtent - position.viewportDimension * 0.8,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(buttonKey), findsNothing);
      position.jumpTo(
        position.maxScrollExtent - position.viewportDimension * 0.7,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(buttonKey), findsOneWidget);
    },
  );

  testWidgets('chapter menu action coalesces taps and targets current pid', (
    tester,
  ) async {
    final locator = _ReaderPostLocator(tid: '100', pid: '5002')
      ..pending = Completer<ApiResult<ThreadPostLocation>>();
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository.threeEpisodes(),
        initialEpisodeId: 'novel:49:100:5002',
        threadRepository: _FakeThreadRepository(targetPid: '5002'),
        threadPostLocator: locator,
      ),
    );
    await tester.pumpAndSettle();
    await _showReaderMenu(tester);
    final action = find.byKey(
      const Key('shared-reader-bottom-action-chapter-interactions'),
    );
    expect(
      find.byKey(const Key('shared-reader-top-action-chapter-interactions')),
      findsNothing,
    );
    expect(
      tester.getCenter(action).dx,
      lessThan(
        tester
            .getCenter(
              find.byKey(const Key('shared-reader-bottom-action-catalog')),
            )
            .dx,
      ),
    );
    final onPressed = tester.widget<ReaderToolButton>(action).onPressed;
    onPressed();
    onPressed();
    await tester.pump();
    expect(locator.calls, 1);
    locator.pending!.complete(locator.location);
    await tester.pumpAndSettle();
    final detail = tester.widget<ThreadDetailPage>(
      find.byType(ThreadDetailPage),
    );
    expect(
      (detail.tid, detail.targetPid, detail.landing),
      ('100', '5002', ThreadPostLanding.bodyEnd),
    );
  });

  testWidgets('chapter change discards late interactions location', (
    tester,
  ) async {
    final locator = _ReaderPostLocator(tid: '100')
      ..pending = Completer<ApiResult<ThreadPostLocation>>();
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository.threeEpisodes(),
        threadPostLocator: locator,
        threadRepository: _FakeThreadRepository(targetPid: '5001'),
      ),
    );
    await tester.pumpAndSettle();
    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-chapter-interactions')),
    );
    await tester.pump();
    expect(locator.calls, 1);
    await _showReaderMenu(tester);
    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('第2章').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('第2章').last);
    await tester.pumpAndSettle();
    locator.pending!.complete(locator.location);
    await tester.pumpAndSettle();
    expect(find.byType(ThreadDetailPage), findsNothing);
    expect(_readerText('第三段。'), findsOneWidget);
  });

  testWidgets('invalid chapter pid hides dedicated actions', (tester) async {
    final original = _FakeNovelRepository();
    final episode = original.episodes.first;
    final repository = _FakeNovelRepository(
      episodes: [
        NovelEpisodeItem(
          episodeId: episode.episodeId,
          novelId: episode.novelId,
          sourceTid: episode.sourceTid,
          episodeTitle: episode.episodeTitle,
          orderIndex: episode.orderIndex,
        ),
      ],
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('novel-reader-chapter-interactions-button')),
      findsNothing,
    );
    await _showReaderMenu(tester);
    expect(
      find.byKey(const Key('shared-reader-bottom-action-chapter-interactions')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('shared-reader-top-action-open-thread')),
      findsOneWidget,
    );
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
            forumImageRefererProvider.overrideWithValue(
              'https://bbs.yamibo.com/',
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
            forumImageRefererProvider.overrideWithValue(
              'https://bbs.yamibo.com/',
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

  testWidgets(
    'NovelReaderPage paged overscroll returns to the previous chapter',
    (tester) async {
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
    },
  );

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

  for (final filtered in [false, true]) {
    testWidgets(
      'reader floor link preserves identity and return position filtered=$filtered',
      (tester) async {
        final locator = _ReaderPostLocator();
        final repository = _FakeNovelRepository(
          firstRawHtml:
              '<p><a href="forum.php?mod=viewthread&amp;tid=200&amp;page=4${filtered ? '&amp;authorid=10&amp;ordertype=1' : ''}#pid5001">Target floor</a></p>'
              '${List.filled(80, '<p>Chapter body.</p>').join()}',
          firstParagraphs: const ['Target floor'],
        );
        await tester.pumpWidget(
          _buildReaderApp(
            repository: repository,
            threadRepository: _FakeThreadRepository(targetPid: '5001'),
            threadPostLocator: locator,
          ),
        );
        await tester.pumpAndSettle();
        final scrollable = find.descendant(
          of: find.byKey(const Key('novel-reader-paragraph-list')),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        final before = position.pixels;
        await tester.tapAt(
          tester.getTopLeft(_readerText('Target floor')) + const Offset(8, 8),
        );
        await tester.pumpAndSettle();
        final page = tester.widget<ThreadDetailPage>(
          find.byType(ThreadDetailPage),
        );
        expect(page.tid, '200');
        expect(page.targetPid, '5001');
        expect(page.initialPage, filtered ? 2 : 4);
        expect(locator.calls, filtered ? 1 : 0);
        Navigator.of(tester.element(find.byType(ThreadDetailPage))).pop();
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(before, 0.01));
        expect(find.byType(NovelReaderPage), findsOneWidget);
      },
    );
  }

  testWidgets(
    'reader double click opens once and chapter switch discards late location',
    (tester) async {
      final locator = _ReaderPostLocator()
        ..pending = Completer<ApiResult<ThreadPostLocation>>();
      await tester.pumpWidget(
        _buildReaderApp(
          repository: _FakeNovelRepository(
            firstRawHtml:
                '<p><a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=200&amp;pid=5001">Target floor</a></p>',
            firstParagraphs: const ['Target floor'],
          ),
          threadPostLocator: locator,
          threadRepository: _FakeThreadRepository(targetPid: '5001'),
        ),
      );
      await tester.pumpAndSettle();
      final point =
          tester.getTopLeft(_readerText('Target floor')) + const Offset(8, 8);
      await tester.tapAt(point);
      await tester.tapAt(point);
      await tester.pump();
      expect(locator.calls, 1);
      await _showReaderMenu(tester);
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-catalog')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('第2章').last);
      await tester.pumpAndSettle();
      locator.pending!.complete(locator.location);
      await tester.pumpAndSettle();
      expect(find.byType(ThreadDetailPage), findsNothing);
      expect(_readerText('第三段。'), findsOneWidget);
    },
  );

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

      expect(
        find.byKey(const Key('novel-reader-delayed-loading-indicator')),
        findsNothing,
      );

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

Future<void> _pumpVerticalReaderReady(WidgetTester tester) async {
  for (var frame = 0; frame < 300; frame++) {
    // Long HTML may be prepared on a worker isolate, outside the test clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (find
            .byKey(const Key('novel-reader-paragraph-list'))
            .evaluate()
            .isNotEmpty &&
        find
            .byKey(const Key('novel-reader-delayed-loading-surface'))
            .evaluate()
            .isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  expect(
    find.byKey(const Key('novel-reader-delayed-loading-surface')),
    findsNothing,
  );
  expect(find.byKey(const Key('novel-reader-paragraph-list')), findsOneWidget);
}

ScrollPosition _verticalPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('novel-reader-paragraph-list')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Future<void> _tapPagedReaderZone(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(ReaderPagedTurnMotion.tapConfirmationDelay);
  await tester.pump(ReaderPagedTurnMotion.animationDuration);
  await tester.pumpAndSettle();
}

Finder _readerText(String text) {
  return find.byWidgetPredicate((widget) {
    return widget is RichText && widget.text.toPlainText().contains(text);
  });
}

Widget _buildReaderApp({
  required _FakeNovelRepository repository,
  NovelReaderPreferencesRepository? preferencesRepository,
  NovelReaderProgressCommitter? progressCommitter,
  LibraryStateRepository? stateRepository,
  ThreadRepository? threadRepository,
  ThreadPostLocator? threadPostLocator,
  NovelReaderDocumentBuildService? documentBuildService,
  NovelReaderSupplementalHydrationService? supplementalHydrationService,
  NovelChapterUpdateService? chapterUpdateService,
  ThemeData? theme,
  ValueListenable<ThemeData>? themeListenable,
  String initialEpisodeId = 'novel:49:100:5001',
  Widget? home,
  _FakeNovelChapterDockRepository? dockRepository,
}) {
  dockRepository ??= _FakeNovelChapterDockRepository();
  return ProviderScope(
    overrides: [
      novelChapterInteractionsDockPreferencesRepositoryProvider
          .overrideWithValue(dockRepository),
      novelRepositoryProvider.overrideWithValue(repository),
      novelReaderPreferencesRepositoryProvider.overrideWithValue(
        preferencesRepository ??
            _FakeNovelReaderPreferencesRepository(repository),
      ),
      if (progressCommitter != null)
        novelReaderProgressCommitterProvider.overrideWithValue(
          progressCommitter,
        ),
      novelChapterUpdateServiceProvider.overrideWithValue(
        chapterUpdateService ?? _RecordingNovelChapterUpdateService(),
      ),
      forumWebViewExternalLauncherProvider.overrideWithValue(
        _FakeForumWebViewExternalLauncher(),
      ),
      forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
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
      if (threadPostLocator != null)
        threadPostLocatorProvider.overrideWithValue(threadPostLocator),
    ],
    child: themeListenable == null
        ? LocalizedTestApp(
            theme: theme,
            home:
                home ??
                NovelReaderPage(
                  novelId: 'novel:49:100',
                  initialEpisodeId: initialEpisodeId,
                ),
          )
        : ValueListenableBuilder<ThemeData>(
            valueListenable: themeListenable,
            builder: (context, activeTheme, child) {
              return LocalizedTestApp(
                theme: activeTheme,
                home:
                    home ??
                    NovelReaderPage(
                      novelId: 'novel:49:100',
                      initialEpisodeId: initialEpisodeId,
                    ),
              );
            },
          ),
  );
}

final class _FakeNovelChapterDockRepository
    implements NovelChapterInteractionsDockPreferencesRepository {
  _FakeNovelChapterDockRepository({this.failSave = false});

  final bool failSave;
  NovelChapterInteractionsDockPreferences current =
      const NovelChapterInteractionsDockPreferences();

  @override
  Future<NovelChapterInteractionsDockPreferences> load() async => current;

  @override
  Future<void> save(NovelChapterInteractionsDockPreferences preferences) async {
    if (failSave) throw StateError('save failed');
    current = preferences;
  }
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
  Future<NovelChapterSyncResult> update(
    String novelId, {
    NovelChapterUpdateIntent intent = NovelChapterUpdateIntent.normal,
  }) async {
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

class _ReaderPostLocator implements ThreadPostLocator {
  _ReaderPostLocator({this.tid = '200', this.pid = '5001'});

  final String tid;
  final String pid;
  var calls = 0;
  Completer<ApiResult<ThreadPostLocation>>? pending;
  ApiResult<ThreadPostLocation> get location =>
      ApiSuccess(ThreadPostLocation(tid: tid, pid: pid, page: 2, url: ''));
  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) async {
    calls++;
    return pending == null ? location : await pending!.future;
  }
}

class _FakeThreadRepository implements ThreadRepository {
  _FakeThreadRepository({this.targetPid});
  final String? targetPid;
  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    return DataReadSuccess(
      data: ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: '测试小说',
        author: 'alice',
        replies: 0,
        views: 1,
        currentPage: page,
        perPage: 20,
        posts: [
          if (targetPid != null)
            ThreadPost(
              pid: targetPid!,
              author: 'Author',
              authorId: '10',
              message: '<p>Target body</p>',
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
       preferences =
           preferences ??
           NovelReaderPreferences.defaults().copyWith(
             flowMode: NovelReaderFlowMode.vertical,
           );

  factory _FakeNovelRepository.threeEpisodes({
    List<String>? firstParagraphs,
    NovelReadingProgress? readingProgress,
    Duration chapterLoadDelay = Duration.zero,
    Set<String> failedEpisodeIds = const <String>{},
    NovelReaderPreferences? preferences,
  }) {
    return _FakeNovelRepository(
      preferences: preferences,
      episodes: _threeEpisodes(),
      contentsByEpisodeId: _contentsForParagraphs(<String, List<String>>{
        'novel:49:100:5001': firstParagraphs ?? <String>['第一段。', '第二段。'],
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
  final savedProgressEpisodeIds = <String>[];
  final savedProgressOffsets = <double>[];
  final chapterLoadEpisodeIds = <String>[];
  final chapterLoadGates = <String, Completer<void>>{};
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
    chapterLoadEpisodeIds.add(episodeId);
    final gate = chapterLoadGates[episodeId];
    if (gate != null) await gate.future;
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
    savedProgressOffsets.add(scrollOffset);
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

class _ControlledPageProgressCommitter implements NovelReaderProgressCommitter {
  _ControlledPageProgressCommitter(
    _FakeNovelRepository repository, {
    this.forwardScheduledCommits = false,
  }) : _delegate = DefaultNovelReaderProgressCommitter(repository: repository);

  final DefaultNovelReaderProgressCommitter _delegate;
  final bool forwardScheduledCommits;
  final flushes = <_PendingPageProgressFlush>[];
  Future<void> _tail = Future<void>.value();

  @override
  void schedule(NovelReaderProgressSnapshot snapshot) {
    if (forwardScheduledCommits) _delegate.schedule(snapshot);
  }

  @override
  Future<void> flush(NovelReaderProgressSnapshot snapshot) {
    final pending = _PendingPageProgressFlush(snapshot);
    flushes.add(pending);
    final operation = _tail.then((_) async {
      await pending.completer.future;
      await _delegate.flush(snapshot);
    });
    _tail = operation.catchError((_) {});
    return operation;
  }

  @override
  void cancel() => _delegate.cancel();
}

class _PendingPageProgressFlush {
  _PendingPageProgressFlush(this.snapshot);

  final NovelReaderProgressSnapshot snapshot;
  final completer = Completer<void>();

  void complete() {
    if (!completer.isCompleted) completer.complete();
  }
}

class _ControlledPagePreferencesRepository
    implements NovelReaderPreferencesRepository {
  _ControlledPagePreferencesRepository(this.repository);

  final _FakeNovelRepository repository;
  final saves = <_PendingPagePreferencesSave>[];

  @override
  Future<NovelReaderPreferences> load() async => repository.preferences;

  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    final save = _PendingPagePreferencesSave();
    saves.add(save);
    repository.upsertPreferencesCallCount += 1;
    await save.completer.future;
    repository.latestPreferences = preferences;
    repository.preferences = preferences;
  }
}

class _PendingPagePreferencesSave {
  final completer = Completer<void>();

  void complete() => completer.complete();
  void fail() => completer.completeError(StateError('preferences save failed'));
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
