import '../../tool/legacy/novel/legacy_reader_surface.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../tool/novel_main_page_profile_data.dart';
import '../../tool/novel_main_page_profile_observation.dart';

void main() {
  _testRule(heading: false);
  _testRule(heading: true);
}

void _testRule({required bool heading}) {
  const style = 'font-size:20px;line-height:32px;margin:0';
  testWidgets(
    '${heading ? 'Heading keep' : 'Line balance'} reflows at the saved anchor',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(800, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferencesNovelReaderPreferencesRepository repository() =>
          SharedPreferencesNovelReaderPreferencesRepository(
            preferencesStore: SharedPreferencesStore(),
            legacySource: const _NoLegacy(),
          );
      final preferences = repository();
      await preferences.save(
        profileReaderPreferences.copyWith(
          viewport: const NovelReaderViewportOverrides(
            top: 96,
            bottom: 96,
            contentWidth: NovelReaderContentWidth.limited(160),
          ),
        ),
      );
      final data = NovelMainPageProfileData();
      final chapter = data.add(
        heading
            ? '<p style="$style">ABCDEFGHIJKLMN</p>'
                  '<h2 style="$style">Title</h2>'
                  '<p style="$style">OPQRSTUVWXYZab</p>'
            : '<p style="$style">ABCDEFGHIJKLMNOPQRSTUVWXYZab</p>',
      );
      final args = NovelReaderArgs(
        novelId: chapter.novelId,
        episodeId: chapter.episodeId,
      );
      final reader = GlobalKey();
      await tester.pumpWidget(
        data.scope(
          MaterialApp(
            theme: ThemeData.light().copyWith(
              textTheme: const TextTheme(
                bodyMedium: TextStyle(fontFamily: 'Ahem'),
              ),
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NovelReaderPage(
              key: reader,
              novelId: chapter.novelId,
              initialEpisodeId: chapter.episodeId,
              nativePagination: true,
              comparisonSurfaceFactory: createLegacyNovelReaderSurface,
              nativeIdleScheduler: () async {},
            ),
          ),
          preferences: preferences,
        ),
      );

      Future<ProfileReaderObservation> wait(
        bool Function(ProfileReaderObservation) accepts,
      ) async {
        for (var frame = 0; frame < 350; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          final observation = observeProfileReader(
            reader.currentContext!,
            args,
          );
          expect(observation.failed, isFalse);
          if (observation.ready &&
              observation.complete &&
              accepts(observation)) {
            return observation;
          }
        }
        fail('Native reader did not publish the expected pages');
      }

      List<List<int>> rows(ProfileReaderObservation observation) => [
        for (final page in observation.nativeController!.snapshot!)
          [
            for (final fragment in page.fragments)
              fragment.endLine - fragment.startLine,
          ],
      ];

      Future<bool> readSetting() async {
        final saved = await repository().load();
        return heading ? saved.keepHeadingWithNext : saved.avoidIsolatedLines;
      }

      Future<void> toggle({required bool from}) async {
        tester
            .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
            .controller!
            .showMenu();
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('shared-reader-bottom-action-display')),
        );
        await tester.pumpAndSettle();
        final context = tester.element(
          find.byKey(const Key('novel-reader-display-settings-sheet')),
        );
        final l10n = AppLocalizations.of(context);
        final control = find.widgetWithText(
          SwitchListTile,
          heading
              ? l10n.novelKeepHeadingWithNext
              : l10n.novelAvoidIsolatedLines,
        );
        await tester.ensureVisible(control);
        expect(tester.widget<SwitchListTile>(control).value, from);
        await tester.tap(control);
        await tester.pump();
        expect(tester.widget<SwitchListTile>(control).value, !from);
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
      }

      try {
        final baseline = await wait((observation) => observation.page == 0);
        final original = baseline.nativeController!.snapshot!;
        final before = heading
            ? const [
                [2, 1],
                [2],
              ]
            : const [
                [3],
                [1],
              ];
        final after = heading
            ? const [
                [2],
                [1, 2],
              ]
            : const [
                [2],
                [2],
              ];
        expect(
          rows(baseline),
          before,
          reason: 'Body ${original.width}×${original.height}',
        );
        final originalFirstPage = original.first;
        baseline.overlay!.onRightTap!();
        final tail = await wait(
          (observation) =>
              observation.page == 1 && observation.businessConfirmed,
        );
        final oldAnchor = tail.nativeController!
            .viewForPage(1)!
            .coverage
            .points
            .first
            .anchor;

        await toggle(from: false);
        final balanced = await wait(
          (observation) =>
              observation.paginationKey != baseline.paginationKey &&
              observation.businessConfirmed,
        );
        expect(rows(balanced), after);
        expect(balanced.page, 1);
        expect(
          balanced.nativeController!.viewForPage(1)!.coverage.locate(oldAnchor),
          isNotNull,
        );
        expect(original.first, same(originalFirstPage));
        expect(await readSetting(), isTrue);

        await toggle(from: true);
        final restored = await wait(
          (observation) => observation.paginationKey == baseline.paginationKey,
        );
        expect(rows(restored), before);
        expect(await readSetting(), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
}

final class _NoLegacy implements NovelReaderPreferencesLegacySource {
  const _NoLegacy();

  @override
  Future<NovelReaderPreferences?> load() async => null;
}
