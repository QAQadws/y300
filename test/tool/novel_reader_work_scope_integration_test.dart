import '../../tool/legacy/novel/legacy_reader_surface.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/fonts/data/services/flutter_font_runtime_loader.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preset_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../tool/novel_main_page_profile_data.dart';
import '../../tool/novel_main_page_profile_observation.dart';

void main() {
  testWidgets('reading scope isolates works and reset preserves the anchor', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(800, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = SharedPreferencesNovelReaderPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
      legacySource: const _NoLegacy(),
    );
    final defaults = profileReaderPreferences.copyWith(
      fontSize: 20,
      viewport: const NovelReaderViewportOverrides(
        contentWidth: NovelReaderContentWidth.limited(160),
      ),
    );
    await repo.save(defaults);
    final data = NovelMainPageProfileData();
    final html = List.generate(
      20,
      (i) => '<p>Readable paragraph ${i + 1}.</p>',
    ).join();
    final a = data.add(html);
    final b = data.add(html);
    final bookmark = NovelReaderBookmark(
      bookmarkId: 'episode-bookmark:${a.episodeId}',
      novelId: a.novelId,
      episodeId: a.episodeId,
      anchor: NovelReaderTextAnchor(episodeId: a.episodeId),
      title: 'Existing bookmark',
      snippet: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await data.addReaderBookmark(bookmark: bookmark);
    final navigator = GlobalKey<NavigatorState>();
    final fonts = FontLibraryService(
      repository: const _NoFonts(),
      runtimeLoader: FlutterFontRuntimeLoader(),
    );
    addTearDown(fonts.dispose);
    final fixture = data.scope(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData.light().copyWith(
          textTheme: const TextTheme(bodyMedium: TextStyle(fontFamily: 'Ahem')),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(),
      ),
      preferences: repo,
    ) as ProviderScope;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fixture.overrides,
          fontLibraryServiceProvider.overrideWithValue(fonts),
        ],
        child: fixture.child,
      ),
    );

    var reader = GlobalKey();
    late NovelReaderArgs args;
    Future<void> open(({String novelId, String episodeId}) work) {
      reader = GlobalKey();
      args = NovelReaderArgs(novelId: work.novelId, episodeId: work.episodeId);
      return navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => NovelReaderPage(
            key: reader,
            novelId: work.novelId,
            initialEpisodeId: work.episodeId,
            nativePagination: true,
            comparisonSurfaceFactory: createLegacyNovelReaderSurface,
            nativeIdleScheduler: () async {},
          ),
        ),
      );
    }

    NovelReaderViewState state() => ProviderScope.containerOf(
      reader.currentContext!,
      listen: false,
    ).read(novelReaderControllerProvider(args)).requireValue;

    Future<ProfileReaderObservation> wait(
      bool Function(ProfileReaderObservation) accepts,
    ) async {
      for (var frame = 0; frame < 500; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        final context = reader.currentContext;
        if (context == null) continue;
        final observation = observeProfileReader(context, args);
        expect(observation.failed, isFalse);
        if (observation.ready && observation.complete && accepts(observation)) {
          return observation;
        }
      }
      fail('Reader did not reach the scoped preferences');
    }

    const sheetKey = Key('novel-reader-display-settings-sheet');
    const scopeKey = Key('novel-reader-settings-scope');
    Future<void> settings() async {
      tester
          .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
          .controller!
          .showMenu();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('shared-reader-bottom-action-display')),
      );
      await tester.pumpAndSettle();
    }

    Future<void> scope(NovelReaderPreferenceScope target) async {
      final control = find.byKey(scopeKey);
      final l10n = AppLocalizations.of(tester.element(control));
      final label = find.descendant(
        of: control,
        matching: find.text(
          target == NovelReaderPreferenceScope.defaults
              ? l10n.novelReaderSettingsDefaults
              : l10n.novelReaderSettingsWork,
        ),
      );
      await tester.ensureVisible(label);
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<NovelReaderPreferenceScope>>(control)
            .selected,
        {target},
      );
    }

    Future<void> slide(String id, {required bool maximum}) async {
      final slider = find.descendant(
        of: find.byKey(Key('novel-reader-$id-slider')),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(slider);
      final rect = tester.getRect(slider);
      await tester.tapAt(
        maximum
            ? rect.centerRight - const Offset(1, 0)
            : rect.centerLeft + const Offset(1, 0),
      );
      await tester.pump();
    }

    Future<void> dismissSettings() async {
      Navigator.of(tester.element(find.byKey(sheetKey))).pop();
      await tester.pumpAndSettle();
    }

    Future<void> closeReader(Future<void> popped) async {
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await popped;
    }

    try {
      var popped = open(a);
      final first = await wait((value) => value.page == 0);
      expect(first.count, greaterThan(2));
      first.overlay!.onRightTap!();
      final tail = await wait(
        (value) => value.page == 1 && value.businessConfirmed,
      );
      final original = state().progressSnapshot;
      final anchor = NovelReaderTextAnchor(
        episodeId: original.episodeId,
        nodeId: original.anchorNodeId,
        textOffset: original.anchorTextOffset,
        formatVersion: original.anchorFormatVersion,
        textIdentity: original.anchorTextIdentity,
      );
      expect(anchor.hasCanonicalTextOffset, isTrue);
      void expectAnchor(ProfileReaderObservation observation) {
        expect(
          observation.nativeController!
              .viewForPage(observation.page!)!
              .coverage
              .locate(anchor),
          isNotNull,
        );
        expect(state().progressSnapshot.anchorNodeId, anchor.nodeId);
        expect(state().progressSnapshot.anchorTextOffset, anchor.textOffset);
      }

      await settings();
      await scope(NovelReaderPreferenceScope.work);
      await slide('font-size', maximum: true);
      await scope(NovelReaderPreferenceScope.defaults);
      expect(state().persistedPreferences.fontSize, 30);
      expect((await repo.load()).fontSize, 20);
      await dismissSettings();
      final local = await wait(
        (value) =>
            value.paginationKey != tail.paginationKey &&
            state().persistedPreferences.fontSize == 30,
      );
      expectAnchor(local);
      await settings();
      await scope(NovelReaderPreferenceScope.defaults);
      await slide('font-size', maximum: false);
      await slide('line-height', maximum: true);
      await dismissSettings();
      final inherited = await wait(
        (value) =>
            value.paginationKey != local.paginationKey &&
            state().persistedPreferences.lineHeight == 2.4,
      );
      expect(state().preferences.fontSize, 30);
      expectAnchor(inherited);
      expect((await repo.load()).fontSize, 14);
      await closeReader(popped);

      popped = open(b);
      await wait((value) => value.page == 0);
      expect(state().preferences.fontSize, 14);
      expect(state().preferences.lineHeight, 2.4);
      expect(state().preferenceScopes!.hasWorkOverrides, isFalse);
      await closeReader(popped);

      popped = open(a);
      final reopened = await wait(
        (value) => state().preferences.fontSize == 30,
      );
      expectAnchor(reopened);
      await settings();
      await tester.tap(
        find.byKey(const Key('novel-reader-reset-work-settings')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('novel-reader-confirm-reset-work-settings')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(sheetKey), findsOneWidget);
      await dismissSettings();
      final reset = await wait(
        (value) =>
            state().preferences.fontSize == 14 &&
            value.paginationKey != reopened.paginationKey,
      );
      expectAnchor(reset);
      expect(state().preferenceScopes!.hasWorkOverrides, isFalse);
      expect(await data.listReaderBookmarks(novelId: a.novelId), [bookmark]);
      expect(
        (await data.getChapterProgress(
          novelId: a.novelId,
          episodeId: a.episodeId,
        ))?.anchorNodeId,
        anchor.nodeId,
      );

      final missingFont = 'a' * 64;
      final presets = SharedPreferencesNovelReaderPresetRepository(
        SharedPreferencesStore(),
      );
      await presets.save(
        'Missing imported font',
        state().persistedPreferences.copyWith(
          fontSize: 22,
          fontFamily: missingFont,
        ),
      );
      await settings();
      await scope(NovelReaderPreferenceScope.work);
      final presetButton = find.byKey(const Key('novel-reader-open-presets'));
      await tester.ensureVisible(presetButton);
      await tester.tap(presetButton);
      await tester.pumpAndSettle();
      final preset = find.text('Missing imported font');
      await tester.tap(preset);
      await tester.pumpAndSettle();
      final apply = find.byKey(
        const Key('novel-reader-apply-preset-with-current-font'),
      );
      expect(apply, findsOneWidget);
      expect(state().preferenceScopes!.hasWorkOverrides, isFalse);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await dismissSettings();
      final applied = await wait(
        (value) =>
            state().persistedPreferences.fontSize == 22 &&
            value.paginationKey != reset.paginationKey,
      );
      expectAnchor(applied);
      expect(state().preferences.fontFamily, 'system');
      expect(
        state().preferenceScopes!.fontFamilyScope,
        NovelReaderPreferenceScope.defaults,
      );
      expect((await repo.load()).fontSize, 14);
      expect(
        (await presets.load()).single.preferences!.fontFamily,
        missingFont,
      );
      await closeReader(popped);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

final class _NoLegacy implements NovelReaderPreferencesLegacySource {
  const _NoLegacy();
  @override
  Future<NovelReaderPreferences?> load() async => null;
}

final class _NoFonts implements FontLibraryRepository {
  const _NoFonts();

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<List<ImportedFont>> listFonts() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected font I/O: ${invocation.memberName}');
}
