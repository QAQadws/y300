import '../../../../tool/legacy/novel/legacy_reader_surface.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/novel/data/preferences/novel_chapter_interactions_dock_preferences_provider.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_episode_open_policy.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_interactions_dock_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/novel_repository_seed.dart';

const _work = 'novel:49:100';
const _chapter = '$_work:5001';
const _next = '$_work:5003';

enum _BodySample {
  paragraphs,
  rubyPair,
  orphanRuby,
  consecutiveRuby,
  explicitRuby,
  alignedRuby,
  breakRuby,
  rtcRuby,
  underRuby,
  layeredRuby,
  mixedRuby,
  anonymousRuby,
  mixedAnonymousRuby,
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() async {
    await (FontLoader('packages/forum_content_renderer/ForumBodyInlineSpace')
          ..addFont(
            rootBundle.load(
              'packages/forum_content_renderer/assets/fonts/inline_space.ttf',
            ),
          ))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final rtl in [false, true]) {
    for (final root in [false, true]) {
      for (final readOnly in [false, true]) {
        testWidgets(
          'breakable original gap completes at physical EOF (rtl=$rtl root=$root readOnly=$readOnly)',
          (tester) async {
            tester.view.physicalSize = const Size(360, 480);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final fixture = (await tester.runAsync(
              () => _Fixture.create(
                rawBody: (
                  '<p><ruby style="line-height:1"><rb style="font-size:200px">A</rb> <rb style="font-size:200px">B</rb><rb style="font-size:200px">C</rb>${root ? '' : '<rtc>'}<rt style="font-size:20px">xx</rt> <rt style="font-size:20px">yy</rt>${root ? '' : '</rtc>'}</ruby></p>',
                  'A BCxx yy',
                ),
              ),
            ))!;
            try {
              if (readOnly) {
                await tester.runAsync(fixture.seedUnfinishedPosition);
              }
              final before = (await tester.runAsync(
                () => fixture.db.query(AppDatabase.novelReadingProgressTable),
              ))!;
              await tester.pumpWidget(
                fixture.app(
                  nativePagination: true,
                  preferences: NovelReaderPreferences.defaults().copyWith(
                    flowMode: rtl
                        ? NovelReaderFlowMode.pagedRtl
                        : NovelReaderFlowMode.pagedLtr,
                  ),
                ),
              );
              await _pumpNativePageReady(tester, page: readOnly ? 1 : 0);
              final controller = tester
                  .widget<NovelReaderNativePagedViewport>(
                    find.byType(NovelReaderNativePagedViewport),
                  )
                  .controller;
              expect(controller.snapshot!.length, 3);
              await tester.pump(const Duration(milliseconds: 300));
              expect(
                (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
                isNot(true),
              );
              if (readOnly) {
                expect(
                  (await tester.runAsync(
                    () =>
                        fixture.db.query(AppDatabase.novelReadingProgressTable),
                  ))!,
                  before,
                );
              }
              if (!readOnly) {
                await tester.drag(
                  find.byType(NovelReaderNativePagedViewport),
                  Offset(rtl ? 280 : -280, 0),
                );
                await _pumpNativePageReady(tester, page: 1, animate: true);
              }
              // The original source ends with yy. Its EOF is physically visible
              // before unannotated C; it cannot mark the chapter complete.
              expect(
                controller
                    .viewForPage(1)!
                    .coverage
                    .points
                    .any((p) => p.sourceRune == 9),
                isTrue,
              );
              await tester.pump(const Duration(milliseconds: 300));
              expect(
                (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
                isNot(true),
              );
              await tester.drag(
                find.byType(NovelReaderNativePagedViewport),
                Offset(rtl ? 280 : -280, 0),
              );
              await _pumpNativePageReady(tester, page: 2, animate: true);
              final last = controller.viewForPage(2)!;
              expect(last.coverage.hasClippedGlyphs, isFalse);
              expect(
                last.coverage.points.every(
                  (p) => p.sourceRune >= 3 && p.sourceRune <= 4,
                ),
                isTrue,
              );
              await tester.pump(const Duration(milliseconds: 249));
              expect(
                (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
                isNot(true),
              );
              await tester.pump(const Duration(milliseconds: 1));
              final state = await fixture.load(tester);
              expect(state.episodeStates[_chapter]?.isRead, isTrue);
              final progress = state.progressByEpisode[_chapter]!;
              expect(progress.pageIndex, 2);
              expect(progress.anchorFormatVersion, 1);
              expect(
                progress.anchorTextOffset,
                last.coverage.points.first.anchor.textOffset,
              );
              expect(
                progress.anchorTextIdentity,
                last.coverage.points.first.anchor.textIdentity,
              );
            } finally {
              await fixture.close(tester);
            }
          },
        );
      }
    }
  }

  for (final rtl in [false, true]) {
    for (final under in [false, true]) {
      for (final (readOnlyRestore, gap, annotationKind) in [
        for (final readOnly in [false, true])
          for (final gap in ['', ' '])
            for (final annotationKind in [0, 1, 2, 3, 4])
              (readOnly, gap, annotationKind),
      ]) {
        final annotationGap = annotationKind != 0;
        final annotation = switch (annotationKind) {
          1 => '<rtc style="font-size:10px"><rt>x</rt> <rt>y</rt></rtc>',
          2 => '<rt style="font-size:10px">x</rt> <rt style="font-size:10px">y</rt>',
          3 => '<rt style="font-size:10px">漢</rt>\n<rt style="font-size:10px">字</rt>',
          4 => '<rtc style="font-size:10px"><rt>漢</rt>\n<rt>字</rt></rtc>',
          _ => '',
        };
        testWidgets(
          'original spanning component completes only at physical EOF (rtl=$rtl, under=$under, readOnly=$readOnlyRestore, gap=${gap.isNotEmpty}, annotationKind=$annotationKind)',
          (tester) async {
            tester.view.physicalSize = const Size(360, 480);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final fixture = (await tester.runAsync(
              () => _Fixture.create(
                rawBody: (
                  '<p><ruby style="line-height:1;ruby-position:${under ? 'under' : 'over'}"><rb style="font-size:40px">A</rb>$gap<rb style="font-size:40px">B</rb>$annotation<rtc style="font-size:20px">word</rtc><rb style="font-size:200px">C</rb><rb style="font-size:200px">D</rb><rt style="font-size:${annotationGap ? 80 : 100}px">zz</rt>${annotationGap ? '<rtc style="font-size:20px"><rt>tt</rt></rtc>' : ''}</ruby></p>',
                  'A${gap}B${annotationKind >= 3
                      ? '漢\n字'
                      : annotationGap
                      ? 'x y'
                      : ''}wordCDzz${annotationGap ? 'tt' : ''}',
                ),
              ),
            ))!;
            try {
              if (readOnlyRestore) {
                await tester.runAsync(fixture.seedUnfinishedPosition);
              }
              final before = (await tester.runAsync(
                () => fixture.db.query(AppDatabase.novelReadingProgressTable),
              ))!;
              await tester.pumpWidget(
                fixture.app(
                  nativePagination: true,
                  preferences: NovelReaderPreferences.defaults().copyWith(
                    flowMode: rtl
                        ? NovelReaderFlowMode.pagedRtl
                        : NovelReaderFlowMode.pagedLtr,
                  ),
                ),
              );
              await _pumpNativePageReady(tester, page: 0);
              final controller = tester
                  .widget<NovelReaderNativePagedViewport>(
                    find.byType(NovelReaderNativePagedViewport),
                  )
                  .controller;
              expect(controller.snapshot!.length, 2);
              // A real two-base span shares the first row with C+zz. Original
              // semantic EOF is already visible; unannotated D is on page two.
              expect(
                controller
                    .viewForPage(0)!
                    .coverage
                    .points
                    .any(
                      (p) =>
                          p.sourceRune ==
                          10 + gap.length + (annotationGap ? 5 : 0),
                    ),
                isTrue,
              );
              await tester.pump(const Duration(milliseconds: 300));
              expect(
                (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
                isNot(true),
              );
              if (readOnlyRestore) {
                expect(
                  (await tester.runAsync(
                    () =>
                        fixture.db.query(AppDatabase.novelReadingProgressTable),
                  ))!,
                  before,
                );
              }
              await tester.drag(
                find.byType(NovelReaderNativePagedViewport),
                Offset(rtl ? 280 : -280, 0),
              );
              await _pumpNativePageReady(tester, page: 1, animate: true);
              final last = controller.viewForPage(1)!;
              expect(last.coverage.hasClippedGlyphs, isFalse);
              expect(last.coverage.points, isNotEmpty);
              expect(
                last.coverage.points.every(
                  (p) =>
                      p.sourceRune >=
                          7 + gap.length + (annotationGap ? 3 : 0) &&
                      p.sourceRune <= 8 + gap.length + (annotationGap ? 3 : 0),
                ),
                isTrue,
              );
              await tester.pump(const Duration(milliseconds: 249));
              expect(
                (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
                isNot(true),
              );
              await tester.pump(const Duration(milliseconds: 1));
              final state = await fixture.load(tester);
              expect(state.episodeStates[_chapter]?.isRead, isTrue);
              final progress = state.progressByEpisode[_chapter]!;
              expect(progress.pageIndex, 1);
              expect(progress.anchorFormatVersion, 1);
              // Existing semantic parsing omits whitespace-only runs. The real
              // gap advances source runes, not the format1 semantic coordinate.
              expect(progress.anchorTextOffset, 7 + (annotationGap ? 2 : 0));
              expect(
                progress.anchorTextIdentity,
                last.coverage.points.first.anchor.textIdentity,
              );
              expect(
                progress.anchorTextOffset,
                last.coverage.points.first.anchor.textOffset,
              );
            } finally {
              await fixture.close(tester);
            }
          },
        );
      }
    }
  }

  for (final (rtl, rtc, under, levelCount) in [
    for (final rtl in [false, true])
      for (final rtc in [false, true])
        for (final under in [false, true]) (rtl, rtc, under, 1),
    for (final rtl in [false, true])
      for (final under in [false, true]) ...[
        (rtl, true, under, 2),
        (rtl, false, under, 3),
      ],
  ]) {
    for (final readOnlyRestore in [false, true]) {
      testWidgets(
        'reordered ruby completes only at its actual final page (rtl=$rtl, RTC=$rtc, under=$under, levels=$levelCount, readOnly=$readOnlyRestore)',
        (tester) async {
          tester.view.physicalSize = const Size(360, 480);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final fixture = (await tester.runAsync(
            () => _Fixture.create(
              rawBody: (
                '<p><ruby style="line-height:1;ruby-position:${under ? 'under' : 'over'}"><rb style="font-size:200px">A</rb><rb style="font-size:200px">B</rb>${rtc ? '<rtc>' : ''}<rt style="font-size:${levelCount == 1 ? 100 : 70}px">xx</rt>${rtc ? '</rtc>' : ''}${levelCount >= 2 ? '<rtc><rt style="font-size:20px">uu</rt></rtc>' : ''}${levelCount >= 3 ? '<rt style="font-size:10px">zz</rt>' : ''}</ruby></p>',
                'ABxx${levelCount >= 2 ? 'uu' : ''}${levelCount >= 3 ? 'zz' : ''}',
              ),
            ),
          ))!;
          try {
            if (readOnlyRestore) {
              await tester.runAsync(fixture.seedUnfinishedPosition);
            }
            final before = (await tester.runAsync(
              () => fixture.db.query(AppDatabase.novelReadingProgressTable),
            ))!;
            await tester.pumpWidget(
              fixture.app(
                nativePagination: true,
                preferences: NovelReaderPreferences.defaults().copyWith(
                  flowMode: rtl
                      ? NovelReaderFlowMode.pagedRtl
                      : NovelReaderFlowMode.pagedLtr,
                ),
              ),
            );
            await _pumpNativePageReady(tester, page: 0);
            final controller = tester
                .widget<NovelReaderNativePagedViewport>(
                  find.byType(NovelReaderNativePagedViewport),
                )
                .controller;
            expect(controller.snapshot!.length, 2);
            // All annotation levels belong to A. Their semantic end is visible
            // on page zero, before the actual terminal page containing only B.
            final sourceEnd = 2 + levelCount * 2;
            final semanticEnd = controller
                .viewForPage(0)!
                .coverage
                .points
                .firstWhere((point) => point.sourceRune == sourceEnd);
            expect(semanticEnd.anchor.textOffset, sourceEnd);
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
              isNot(true),
            );
            if (readOnlyRestore) {
              expect(
                (await tester.runAsync(
                  () => fixture.db.query(AppDatabase.novelReadingProgressTable),
                ))!,
                before,
              );
            }
            await tester.drag(
              find.byType(NovelReaderNativePagedViewport),
              Offset(rtl ? 280 : -280, 0),
            );
            await _pumpNativePageReady(tester, page: 1, animate: true);
            final last = controller.viewForPage(1)!;
            expect(last.coverage.hasClippedGlyphs, isFalse);
            expect(last.coverage.points, isNotEmpty);
            expect(
              last.coverage.points.every(
                (point) => point.sourceRune >= 1 && point.sourceRune <= 2,
              ),
              isTrue,
            );
            expect(
              (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
              isNot(true),
            );
            await tester.pump(const Duration(milliseconds: 249));
            expect(
              (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
              isNot(true),
            );
            await tester.pump(const Duration(milliseconds: 1));
            final state = await fixture.load(tester);
            expect(state.episodeStates[_chapter]?.isRead, isTrue);
            final progress = state.progressByEpisode[_chapter]!;
            expect(progress.pageIndex, 1);
            expect(progress.anchorFormatVersion, 1);
            expect(progress.anchorTextOffset, 1);
            expect(
              progress.anchorTextOffset,
              last.coverage.points.first.anchor.textOffset,
            );
            expect(
              progress.anchorTextIdentity,
              last.coverage.points.first.anchor.textIdentity,
            );
          } finally {
            await fixture.close(tester);
          }
        },
      );
    }
  }

  for (final body in _BodySample.values) {
    for (final readOnlyRestore in [false, true]) {
      testWidgets(
        'fractional native font leading preserves SQLite reading authority (body=$body, readOnly=$readOnlyRestore)',
        (tester) async {
          final fixture = (await tester.runAsync(
            () => _Fixture.create(body: body),
          ))!;
          try {
            if (readOnlyRestore) {
              await tester.runAsync(fixture.seedUnfinishedPosition);
            }
            final before = (await tester.runAsync(
              () => fixture.db.query(AppDatabase.novelReadingProgressTable),
            ))!;
            await tester.pumpWidget(
              fixture.app(
                nativePagination: true,
                preferences: NovelReaderPreferences.defaults().copyWith(
                  flowMode: NovelReaderFlowMode.pagedLtr,
                  fontSize: 18.5,
                  lineHeight: 1.27,
                ),
              ),
            );
            await _pumpSinglePageReady(tester);
            expect(
              (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
              isNot(true),
            );
            await tester.pump(const Duration(milliseconds: 250));
            final state = await fixture.load(tester);
            expect(
              state.episodeStates[_chapter]?.isRead == true,
              !readOnlyRestore,
            );
            if (readOnlyRestore) {
              await tester.pumpWidget(const SizedBox.shrink());
              await fixture.load(tester);
              expect(
                (await tester.runAsync(
                  () => fixture.db.query(AppDatabase.novelReadingProgressTable),
                ))!,
                before,
              );
            } else {
              expect(state.progressByEpisode[_chapter]!.anchorFormatVersion, 1);
              expect(
                state.progressByEpisode[_chapter]!.anchorTextIdentity,
                isNotEmpty,
              );
            }
          } finally {
            await fixture.close(tester);
          }
        },
      );
    }
  }

  testWidgets(
    'native page persists canonical SQLite completion after stability',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.pumpWidget(fixture.app(nativePagination: true));
        await _pumpSinglePageReady(tester);
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isNot(true),
        );
        await tester.pump(const Duration(milliseconds: 249));
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isNot(true),
        );
        await tester.pump(const Duration(milliseconds: 1));
        final state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isTrue);
        expect(state.progressByEpisode[_chapter]!.anchorFormatVersion, 1);
        expect(
          state.progressByEpisode[_chapter]!.anchorTextIdentity,
          isNotEmpty,
        );
        expect(
          state.progressByEpisode[_chapter]!.paginationKey,
          tester
              .widget<NovelReaderNativePagedViewport>(
                find.byType(NovelReaderNativePagedViewport),
              )
              .controller
              .paginationKey,
        );
        expect(state.recentEpisodeId, _chapter);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'native passive compatibility restore leaves the SQLite row intact',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.runAsync(fixture.seedUnfinishedPosition);
        final before = (await tester.runAsync(
          () => fixture.db.query(AppDatabase.novelReadingProgressTable),
        ))!;
        await tester.pumpWidget(fixture.app(nativePagination: true));
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(seconds: 1));
        var state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isNot(true));
        await tester.pumpWidget(const SizedBox());
        state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isNot(true));
        expect(
          (await tester.runAsync(
            () => fixture.db.query(AppDatabase.novelReadingProgressTable),
          ))!,
          before,
        );
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'native real chapter turns commit and rearm through the main page',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.runAsync(fixture.seedUnfinishedPosition);
        await tester.pumpWidget(fixture.app(nativePagination: true));
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isNot(true),
        );
        tester
            .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
            .onRightTap!();
        await _pumpSinglePageReady(tester, episode: _next, advanceTime: true);
        final state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isTrue);
        expect(state.progressByEpisode[_chapter]!.anchorFormatVersion, 1);
        tester
            .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
            .onLeftTap!();
        await _pumpSinglePageReady(tester, advanceTime: true);
        tester
            .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
            .onRightTap!();
        await _pumpSinglePageReady(tester, episode: _next, advanceTime: true);
        expect(_readerState(tester).currentEpisode.episodeId, _next);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'the first fully readable single page completes after stability',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.pumpWidget(fixture.app());
        await _pumpSinglePageReady(tester);
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isNot(true),
        );
        await tester.pump(const Duration(milliseconds: 249));
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isNot(true),
        );
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        final state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isTrue);
        expect(
          state.progressByEpisode[_chapter]!.isProgressPercentValid,
          isTrue,
        );
        expect(state.recentEpisodeId, _chapter);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'passive single-page restoration keeps unfinished history intact',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.runAsync(fixture.seedUnfinishedPosition);
        final before = (await tester.runAsync(
          () => fixture.db.query(AppDatabase.novelReadingProgressTable),
        ))!;
        await tester.pumpWidget(fixture.app());
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(seconds: 1));
        final state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isNot(true));
        expect(state.progressByEpisode[_chapter]!.progressPercent, .42);
        final after = (await tester.runAsync(
          () => fixture.db.query(AppDatabase.novelReadingProgressTable),
        ))!;
        expect(after, before);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets('leaving before stability cannot complete a single page', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_Fixture.create))!;
    final navigation = GlobalKey<NavigatorState>();
    try {
      await tester.pumpWidget(fixture.app(navigation: navigation));
      await _pumpSinglePageReady(tester);
      await tester.pump(const Duration(milliseconds: 100));
      unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const Scaffold()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
        isNot(true),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'turning to the next chapter preserves completed single-page state',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.pumpWidget(fixture.app());
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(milliseconds: 300));
        await fixture.load(tester);
        await tester.drag(
          find.byKey(const Key('novel-reader-paged-page-view')),
          const Offset(-200, 0),
        );
        await _pumpSinglePageReady(tester, episode: _next, advanceTime: true);
        final state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isTrue);
        expect(state.progressByEpisode.containsKey(_chapter), isTrue);
        expect(_readerState(tester).currentEpisode.episodeId, _next);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'a real forward chapter swipe confirms a passively restored single page',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.runAsync(fixture.seedUnfinishedPosition);
        await tester.pumpWidget(fixture.app());
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(seconds: 1));
        var state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isNot(true));
        expect(state.progressByEpisode[_chapter]!.progressPercent, .42);

        await tester.drag(
          find.byKey(const Key('novel-reader-paged-page-view')),
          const Offset(-200, 0),
        );
        await _pumpSinglePageReady(tester, episode: _next, advanceTime: true);
        state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isTrue);
        expect(_readerState(tester).currentEpisode.episodeId, _next);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'explicitly restarting a one-page chapter confirms its full body',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.runAsync(fixture.seedUnfinishedPosition);
        await tester.pumpWidget(
          fixture.app(openPolicy: NovelEpisodeOpenPolicy.startAtBeginning),
        );
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(milliseconds: 300));
        final state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isTrue);
        expect(state.progressByEpisode[_chapter]!.progressPercent, 0);
        expect(state.recentEpisodeId, _chapter);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'a failed completion refresh reports an error and permits chapter-turn retry',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.pumpWidget(fixture.app());
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isTrue,
        );
        // Target the additional edge reconciliation read rather than the
        // initial completion write's asynchronous read-model publication.
        await _pumpUntil(
          tester,
          () =>
              _readerState(tester)
                  .readingState
                  ?.episodeStates[_chapter]
                  ?.isRead ==
              true,
        );
        final failureMessage = AppLocalizations.of(
          tester.element(find.byType(NovelReaderPage)),
        ).novelSaveReadingProgressFailed;
        fixture.repository.failNextStateRead = true;

        await tester.drag(
          find.byKey(const Key('novel-reader-paged-page-view')),
          const Offset(-200, 0),
        );
        await _pumpUntil(
          tester,
          () => fixture.repository.injectedStateReadFailures == 1,
        );
        await tester.pump(const Duration(milliseconds: 260));
        expect(_readerState(tester).currentEpisode.episodeId, _chapter);
        expect(find.text(failureMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isTrue,
        );

        await tester.drag(
          find.byKey(const Key('novel-reader-paged-page-view')),
          const Offset(-200, 0),
        );
        await _pumpSinglePageReady(tester, episode: _next, advanceTime: true);
        expect(_readerState(tester).currentEpisode.episodeId, _next);
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isTrue,
        );
        expect(fixture.repository.injectedStateReadFailures, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 250; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('The asynchronous reading-state boundary did not become ready');
}

Future<void> _pumpNativePageReady(
  WidgetTester tester, {
  required int page,
  bool animate = false,
}) async {
  for (var frame = 0; frame < 250; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(
      animate ? const Duration(milliseconds: 16) : Duration.zero,
    );
    final viewport = find.byType(NovelReaderNativePagedViewport);
    if (viewport.evaluate().isEmpty) continue;
    final controller = tester
        .widget<NovelReaderNativePagedViewport>(viewport)
        .controller;
    if (!controller.isSuspended &&
        controller.snapshot?.isComplete == true &&
        controller.visiblePageIndex == page &&
        !controller.hasPendingNavigation) {
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return;
    }
  }
  fail('The final native page did not become readable');
}

Future<void> _pumpSinglePageReady(
  WidgetTester tester, {
  String episode = _chapter,
  bool advanceTime = false,
}) async {
  for (var frame = 0; frame < 250; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(
      advanceTime ? const Duration(milliseconds: 16) : Duration.zero,
    );
    if (tester
        .widget<NovelReaderPage>(find.byType(NovelReaderPage))
        .nativePagination) {
      final viewport = find.byType(NovelReaderNativePagedViewport);
      if (viewport.evaluate().isEmpty ||
          _readerState(tester).currentEpisode.episodeId != episode) {
        continue;
      }
      final controller = tester
          .widget<NovelReaderNativePagedViewport>(viewport)
          .controller;
      if (!controller.isSuspended &&
          controller.snapshot?.isComplete == true &&
          controller.visiblePageIndex == 0 &&
          !controller.hasPendingNavigation) {
        expect(controller.snapshot!.length, 1);
        await tester.pump();
        await tester.pump();
        await tester.pump();
        return;
      }
      continue;
    }
    final surface = find.byType(NovelReaderHtmlPagedSurface);
    final pageView = find.byKey(const Key('novel-reader-paged-page-view'));
    if (surface.evaluate().isNotEmpty &&
        pageView.evaluate().isNotEmpty &&
        _readerState(tester).currentEpisode.episodeId == episode &&
        tester.widget<NovelReaderHtmlPagedSurface>(surface).episode.episodeId ==
            episode &&
        tester
                .widget<NovelReaderHtmlPagedSurface>(surface)
                .paginationCache!
                .length >
            0) {
      expect(
        tester.widget<PageView>(pageView).childrenDelegate.estimatedChildCount,
        1,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return;
    }
  }
  fail('A final readable single-page chapter did not become ready');
}

NovelReaderViewState _readerState(WidgetTester tester) {
  final reader = tester.widget<NovelReaderPage>(find.byType(NovelReaderPage));
  return ProviderScope.containerOf(
        tester.element(find.byType(NovelReaderPage)),
        listen: false,
      )
      .read(
        novelReaderControllerProvider(
          NovelReaderArgs(
            novelId: reader.novelId,
            episodeId: reader.initialEpisodeId,
            openPolicy: reader.openPolicy,
          ),
        ),
      )
      .requireValue;
}

final class _Fixture {
  _Fixture(this.db, this.repository, this.committer);
  final Database db;
  final _ReadFailureRepository repository;
  final DefaultNovelReaderProgressCommitter committer;

  static Future<_Fixture> create({
    _BodySample body = _BodySample.paragraphs,
    (String, String)? rawBody,
  }) async {
    final (rawHtml, plainText) =
        rawBody ??
        switch (body) {
          _BodySample.paragraphs => ('', ''),
          _BodySample.rubyPair => ('<p><ruby>A <rt>x</rt></ruby></p>', 'A x'),
          _BodySample.orphanRuby => ('<p><ruby><rt>x</rt></ruby></p>', 'x'),
          _BodySample.consecutiveRuby => (
            '<p><ruby>A <rt>x</rt><rt>y</rt></ruby></p>',
            'A xy',
          ),
          _BodySample.explicitRuby => (
            '<p><ruby><rb>A</rb><rb> </rb><rb>B</rb><rt>x</rt><rt>·</rt><rt>y</rt></ruby></p>',
            'A Bx·y',
          ),
          _BodySample.alignedRuby => (
            '<p><ruby><rb style="font-size:30px">A</rb><rb style="font-size:20px">B</rb><rt style="font-size:10px">xx</rt><rt style="font-size:15px">yy</rt></ruby></p>',
            'ABxxyy',
          ),
          _BodySample.breakRuby => (
            '<p><ruby>A<rt>x<br>y</rt></ruby></p>',
            'Ax\ny',
          ),
          _BodySample.rtcRuby => (
            '<p><ruby><rb>A</rb><rb>B</rb><rtc><rt>x</rt><rt>y</rt></rtc></ruby></p>',
            'ABxy',
          ),
          _BodySample.underRuby => (
            '<p><ruby><rb>A</rb><rb>B</rb><rtc style="ruby-position:under"><rt>xx</rt><rt>yy</rt></rtc></ruby></p>',
            'ABxxyy',
          ),
          _BodySample.layeredRuby => (
            '<p><ruby><rb>A</rb><rb>B</rb><rtc><rt>xx</rt><rt>yy</rt></rtc><rtc><rt>uu</rt></rtc></ruby></p>',
            'ABxxyyuu',
          ),
          _BodySample.mixedRuby => (
            '<p><ruby>A<rt>xx</rt><rtc><rt>u<br>v</rt></rtc><rt>zz</rt></ruby></p>',
            'Axxu\nvzz',
          ),
          _BodySample.anonymousRuby => (
            '<p><ruby>A<rtc>word<b>bold</b></rtc></ruby></p>',
            'Awordbold',
          ),
          _BodySample.mixedAnonymousRuby => (
            '<p><ruby><rb>A</rb><rb>B</rb><rtc>pre<rt>xx</rt></rtc><rtc><rt>uu</rt><rt>vv</rt></rtc></ruby></p>',
            'ABprexxuuvv',
          ),
        };
    final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
    await seedNovelRepository(
      db,
      seed: const NovelSourceSeed(fid: '49', tid: '100'),
      coverImageUrl: null,
      episodes: rawBody != null || body != _BodySample.paragraphs
          ? [
              NovelEpisodeDraft(
                episodeId: _chapter,
                novelId: _work,
                sourceTid: '100',
                sourcePid: '5001',
                sourcePage: 1,
                episodeTitle: '第1章 开始',
                orderIndex: 0,
                datelineText: '2026-05-03',
                rawHtml: rawHtml,
                plainText: plainText,
                paragraphs: [plainText],
              ),
              ...novelRepositorySeedEpisodes(
                const NovelSourceSeed(fid: '49', tid: '100'),
              ).skip(1),
            ]
          : null,
    );
    final repository = _ReadFailureRepository(Future.value(db));
    return _Fixture(
      db,
      repository,
      DefaultNovelReaderProgressCommitter(repository: repository),
    );
  }

  Widget app({
    GlobalKey<NavigatorState>? navigation,
    NovelEpisodeOpenPolicy openPolicy = NovelEpisodeOpenPolicy.resumeLastRead,
    bool nativePagination = false,
    NovelReaderPreferences? preferences,
  }) => ProviderScope(
    overrides: [
      novelRepositoryProvider.overrideWithValue(repository),
      libraryStateRepositoryProvider.overrideWithValue(
        LocalLibraryStateRepository(Future.value(db)),
      ),
      novelReaderProgressCommitterProvider.overrideWithValue(committer),
      novelReaderPreferencesRepositoryProvider.overrideWithValue(
        _Preferences(preferences),
      ),
      novelChapterInteractionsDockPreferencesRepositoryProvider
          .overrideWithValue(_DisabledDock()),
      forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      imageCacheServiceProvider.overrideWithValue(_UnusedImageCache()),
    ],
    child: LocalizedTestApp(
      navigatorKey: navigation,
      home: NovelReaderPage(
        novelId: _work,
        initialEpisodeId: _chapter,
        openPolicy: openPolicy,
        nativePagination: nativePagination,
        comparisonSurfaceFactory: createLegacyNovelReaderSurface,
        nativeIdleScheduler: _nativeIdle,
      ),
    ),
  );

  Future<void> seedUnfinishedPosition() async {
    await repository.commitProgress(
      progress: NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 123,
        progressPercent: .42,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime.utc(2026, 10, 9),
      ),
    );
  }

  Future<NovelReadingStateSnapshot> load(WidgetTester tester) async {
    NovelReadingStateSnapshot? result;
    Object? failure;
    unawaited(
      repository
          .loadWorkState(novelId: _work)
          .then<void>(
            (value) {
              result = value;
            },
            onError: (Object error, StackTrace _) {
              failure = error;
            },
          ),
    );
    // An application transaction can be waiting for a continuation in the
    // widget's fake-async zone. Keep pumping it while SQLite's isolate replies;
    // awaiting this query from runAsync would park that continuation.
    for (
      var frame = 0;
      frame < 500 && result == null && failure == null;
      frame++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
    if (failure != null) throw failure!;
    expect(
      result,
      isNotNull,
      reason: 'SQLite reading-state query did not finish',
    );
    return result!;
  }

  Future<void> close(WidgetTester tester) async {
    repository.failNextStateRead = false;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    committer.cancel();
    await load(tester);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
      await db.close();
    });
  }
}

Future<void> _nativeIdle() async {}

final class _ReadFailureRepository extends LocalNovelRepository {
  _ReadFailureRepository(super.dbFuture);
  bool failNextStateRead = false;
  int injectedStateReadFailures = 0;

  @override
  Future<NovelReadingStateSnapshot> loadWorkState({required String novelId}) {
    if (failNextStateRead) {
      failNextStateRead = false;
      injectedStateReadFailures++;
      return Future.error(StateError('Controlled completion refresh failure'));
    }
    return super.loadWorkState(novelId: novelId);
  }
}

final class _Preferences implements NovelReaderPreferencesRepository {
  _Preferences([NovelReaderPreferences? value])
    : preferences =
          value ??
          NovelReaderPreferences.defaults().copyWith(
            flowMode: NovelReaderFlowMode.pagedLtr,
          );
  NovelReaderPreferences preferences;
  @override
  Future<NovelReaderPreferences> load() async => preferences;
  @override
  Future<void> save(NovelReaderPreferences value) async => preferences = value;
}

final class _DisabledDock
    implements NovelChapterInteractionsDockPreferencesRepository {
  @override
  Future<NovelChapterInteractionsDockPreferences> load() async =>
      const NovelChapterInteractionsDockPreferences(enabled: false);
  @override
  Future<void> save(NovelChapterInteractionsDockPreferences value) async {}
}

final class _UnusedImageCache implements ImageCacheService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected image-cache call: ${invocation.memberName}');
}
