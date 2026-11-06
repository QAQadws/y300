import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_layout_host.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_surface.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../tool/novel_main_page_profile_data.dart';
import '../../tool/novel_main_page_profile_observation.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('packages/forum_content_renderer/ForumBodyInlineSpace')
          ..addFont(
            rootBundle.load(
              'packages/forum_content_renderer/assets/fonts/inline_space.ttf',
            ),
          ))
        .load();
  });
  for (final mixed in [false, true]) {
    testWidgets(
      'viewport settings persist real geometry and canonical coverage across owners (ruby=$mixed)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesNovelReaderPreferencesRepository repository() =>
            SharedPreferencesNovelReaderPreferencesRepository(
              preferencesStore: SharedPreferencesStore(),
              legacySource: _NoLegacy(),
            );
        final initial = profileReaderPreferences.copyWith(
          fontSize: 20,
          typography: const NovelReaderTypographyOverrides(
            firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
            paragraphSpacing: NovelReaderParagraphSpacing(
              before: 12,
              after: 31,
            ),
            letterSpacing: NovelReaderLetterSpacing(logicalPixels: -1.25),
            wordSpacing: NovelReaderWordSpacing(logicalPixels: 7.5),
            fontWeight: NovelReaderFontWeight(value: 700),
            fontSizeScope: NovelReaderStyleScope.forceBody,
            lineHeightScope: NovelReaderStyleScope.forceBody,
            textAlignment: NovelReaderTextAlignment(
              mode: NovelReaderTextAlignMode.center,
            ),
          ),
        );
        await repository().save(initial);
        final data = NovelMainPageProfileData();
        final source = data.add(
          List.generate(
            32,
            (i) =>
                '<p>Paragraph $i: '
                '${mixed ? 'before <ruby>base<rt>note</rt></ruby> after. ' : ''}'
                'Synthetic native viewport geometry and persistent reading coverage.</p>',
          ).join(),
        );
        final args = NovelReaderArgs(
          novelId: source.novelId,
          episodeId: source.episodeId,
        );
        final navigator = GlobalKey<NavigatorState>();
        final scaler = ValueNotifier<TextScaler>(TextScaler.noScaling);
        addTearDown(scaler.dispose);
        var readerKey = GlobalKey();
        Future<void> mount() => tester.pumpWidget(
          data.scope(
            MaterialApp(
              navigatorKey: navigator,
              theme: ThemeData.light().copyWith(
                textTheme: const TextTheme(
                  bodyMedium: TextStyle(
                    fontFamily: 'Ahem',
                    letterSpacing: 0,
                    wordSpacing: 0,
                  ),
                ),
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => ValueListenableBuilder(
                valueListenable: scaler,
                builder: (context, value, _) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: value),
                  child: child!,
                ),
              ),
              home: const Scaffold(),
            ),
            preferences: repository(),
          ),
        );
        Future<void> open() => navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => NovelReaderPage(
              key: readerKey,
              novelId: source.novelId,
              initialEpisodeId: source.episodeId,
              nativePagination: true,
              nativeIdleScheduler: () async {},
            ),
          ),
        );
        state() => ProviderScope.containerOf(
          readerKey.currentContext!,
          listen: false,
        ).read(novelReaderControllerProvider(args)).value!;
        position() {
          final p = state().progressSnapshot;
          return (
            p.anchorNodeId,
            p.anchorTextOffset,
            p.anchorFormatVersion,
            p.anchorTextIdentity,
          );
        }

        Future<ProfileReaderObservation> wait(
          bool Function(ProfileReaderObservation) accepts,
        ) async {
          for (var i = 0; i < 3000; i++) {
            await tester.pump(Duration(milliseconds: mixed ? 1 : 20));
            if (mixed) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 1)),
              );
            }
            if (readerKey.currentContext case final context?) {
              final observation = observeProfileReader(context, args);
              expect(observation.failed, false);
              if (accepts(observation)) return observation;
            }
          }
          throw StateError('Viewport settings did not settle');
        }

        Future<AppLocalizations> settings() async {
          await tester.tapAt(const Offset(400, 300));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('shared-reader-bottom-action-display')),
          );
          await tester.pumpAndSettle();
          return AppLocalizations.of(
            tester.element(
              find.byKey(const Key('novel-reader-display-settings-sheet')),
            ),
          );
        }

        Future<void> closeSettings() async {
          Navigator.of(
            tester.element(
              find.byKey(const Key('novel-reader-display-settings-sheet')),
            ),
          ).pop();
          await tester.pumpAndSettle();
        }

        Future<void> chooseWidth(String label) async {
          final target = find.descendant(
            of: find.byKey(const Key('novel-reader-viewport-width-mode')),
            matching: find.text(label),
          );
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pump();
        }

        Object? activeDocument;
        void checkGeometry(
          ProfileReaderObservation observation,
          NovelReaderViewportOverrides expected,
          NovelReaderTextAnchor anchor,
        ) {
          expect(state().document, same(activeDocument));
          final viewport = find.byKey(
            const Key('novel-reader-native-paged-surface'),
          );
          final outer = tester.getRect(viewport);
          final surface = tester.widget<NovelReaderNativePagedSurface>(
            find.byType(NovelReaderNativePagedSurface),
          );
          final body = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
          final footer = tester.getRect(
            find.byKey(const Key('novel-reader-native-footer')),
          );
          final left = expected.left ?? 8, right = expected.right ?? 8;
          final top = expected.top ?? 8, bottom = expected.bottom ?? 8;
          final available = outer.width - left - right;
          final limit = expected.contentWidth;
          final desired = limit?.mode == NovelReaderContentWidthMode.available
              ? available
              : (limit?.logicalPixels ?? 720);
          final width = available < desired ? available : desired;
          expect(
            body.left,
            closeTo(outer.left + left + (available - width) / 2, .001),
          );
          expect(
            body.top,
            closeTo(outer.top + top + surface.chromeInsets.topInset, .001),
          );
          expect(body.width, closeTo(width, .001));
          expect(
            body.height,
            closeTo(
              outer.height -
                  top -
                  bottom -
                  surface.chromeInsets.topInset -
                  surface.chromeInsets.persistentBottomInset -
                  footer.height,
              .001,
            ),
          );
          final controller = observation.nativeController!;
          expect(
            (controller.snapshot!.width, controller.snapshot!.height),
            (body.width, body.height),
          );
          final page = controller.viewForPage(observation.page!)!;
          expect(page.coverage.hasClippedGlyphs, false);
          expect(page.coverage.locate(anchor), isNotNull);
          expect(state().preferences.typography, initial.typography);
        }

        await mount();
        var popped = open();
        var observation = await wait((o) => o.ready && o.complete);
        observation.overlay!.onRightTap!();
        observation = await wait(
          (o) => o.ready && o.businessConfirmed && o.page == 1,
        );
        final savedPosition = position();
        final document = state().document;
        activeDocument = document;
        final p = state().progressSnapshot;
        final anchor = NovelReaderTextAnchor(
          episodeId: source.episodeId,
          nodeId: p.anchorNodeId,
          textOffset: p.anchorTextOffset,
          formatVersion: p.anchorFormatVersion,
          textIdentity: p.anchorTextIdentity,
        );
        final oldKey = observation.paginationKey;
        const selected = NovelReaderViewportOverrides(
          left: 0,
          top: 12,
          right: 31,
          bottom: 48,
          contentWidth: NovelReaderContentWidth.limited(480),
        );
        var l10n = await settings();
        for (final edge in NovelReaderViewportEdge.values) {
          final toggle = find.byKey(
            Key('novel-reader-viewport-${edge.name}-enabled'),
          );
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pump();
          tester
              .widget<Slider>(
                find.byKey(Key('novel-reader-viewport-${edge.name}-slider')),
              )
              .onChanged!(selected.marginFor(edge)!);
          await tester.pump();
        }
        await chooseWidth(l10n.novelViewportWidthLimited);
        tester
            .widget<Slider>(
              find.byKey(const Key('novel-reader-viewport-width-slider')),
            )
            .onChanged!(480);
        await closeSettings();
        observation = await wait(
          (o) =>
              o.ready &&
              o.complete &&
              o.paginationKey != oldKey &&
              state().persistedPreferences.viewport == selected,
        );
        expect(state().document, same(document));
        expect(position(), savedPosition);
        checkGeometry(observation, selected, anchor);
        expect((await repository().load()).viewport, selected);
        final firstOwner = observation.nativeOwner!;
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await popped;
        expect(firstOwner.isClosed, true);
        expect(firstOwner.activeCacheHandles, 0);
        expect(firstOwner.estimatedRetainedBytes, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        readerKey = GlobalKey();
        await mount();
        popped = open();
        observation = await wait((o) => o.ready && o.complete);
        expect(position(), savedPosition);
        expect(observation.nativeOwner, isNot(same(firstOwner)));
        activeDocument = state().document;
        checkGeometry(observation, selected, anchor);
        l10n = await settings();
        await chooseWidth(l10n.novelViewportWidthAvailable);
        await closeSettings();
        var expected = selected.withContentWidth(
          const NovelReaderContentWidth.available(logicalPixels: 480),
        );
        observation = await wait(
          (o) =>
              o.ready &&
              o.complete &&
              state().persistedPreferences.viewport == expected,
        );
        expect(position(), savedPosition);
        checkGeometry(observation, expected, anchor);
        await settings();
        final reset = find.byKey(const Key('novel-reader-viewport-left-reset'));
        await tester.ensureVisible(reset);
        await tester.tap(reset);
        await closeSettings();
        expected = expected.withMargin(NovelReaderViewportEdge.left, null);
        observation = await wait(
          (o) =>
              o.ready &&
              o.complete &&
              state().persistedPreferences.viewport == expected,
        );
        expect(position(), savedPosition);
        checkGeometry(observation, expected, anchor);
        await settings();
        final widthReset = find.byKey(
          const Key('novel-reader-viewport-width-reset'),
        );
        await tester.ensureVisible(widthReset);
        await tester.tap(widthReset);
        await closeSettings();
        expected = expected.withContentWidth(null);
        observation = await wait(
          (o) =>
              o.ready &&
              o.complete &&
              state().persistedPreferences.viewport == expected,
        );
        expect(position(), savedPosition);
        checkGeometry(observation, expected, anchor);
        final stored = await repository().load();
        expect(stored.viewport, expected);
        expect(stored.typography, initial.typography);
        if (!mixed) {
          final strings = await settings();
          final triple = find.descendant(
            of: find.byKey(const Key('novel-reader-viewport-columns')),
            matching: find.text(strings.novelViewportTripleColumn),
          );
          await tester.ensureVisible(triple);
          await tester.tap(triple);
          await closeSettings();
          final requested = expected.withColumns(NovelReaderColumnCount.triple);
          Future<ProfileReaderObservation> columns(int count) => wait(
            (o) =>
                o.ready &&
                o.complete &&
                o.nativeController!.snapshot!.columns.count == count &&
                state().persistedPreferences.viewport == requested,
          );
          void checkAnchor(ProfileReaderObservation current) {
            expect(position(), savedPosition);
            expect(
              current.nativeController!.visibleView!.coverage.locate(anchor),
              isNotNull,
            );
          }

          final dormant = await columns(1);
          checkAnchor(dormant);
          expect(dormant.paginationKey, observation.paginationKey);
          await tester.binding.setSurfaceSize(const Size(1040, 560));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final expanded = await columns(3);
          checkAnchor(expanded);
          expect(expanded.paginationKey, isNot(dormant.paginationKey));
          expect(expanded.count, lessThan(dormant.count));
          expect(
            expanded.nativeController!.snapshot!.width,
            greaterThan(initial.contentMaxWidth),
          );
          await tester.binding.setSurfaceSize(const Size(500, 560));
          final narrow = await columns(1);
          checkAnchor(narrow);
          expect(narrow.paginationKey, isNot(expanded.paginationKey));
          expect((await repository().load()).viewport, requested);
          await tester.binding.setSurfaceSize(const Size(1040, 560));
          observation = await columns(3);
          checkAnchor(observation);
          expect(observation.paginationKey, expanded.paginationKey);
          scaler.value = const TextScaler.linear(1.5);
          checkAnchor(await columns(1));
          expect((await repository().load()).viewport, requested);
          scaler.value = TextScaler.noScaling;
          observation = await columns(3);
          checkAnchor(observation);
          final next = observation.page! + 1;
          await tester.drag(find.byType(PageView), const Offset(-620, 0));
          observation = await wait(
            (o) => o.ready && o.businessConfirmed && o.page == next,
          );
          expect(observation.nativeController!.snapshot!.columns.count, 3);
          expect(position(), isNot(savedPosition));
        }
        final finalOwner = observation.nativeOwner!;
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await popped;
        expect(finalOwner.isClosed, true);
        expect(finalOwner.activeCacheHandles, 0);
        expect(finalOwner.estimatedRetainedBytes, 0);
        data.release(source.episodeId);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

final class _NoLegacy implements NovelReaderPreferencesLegacySource {
  @override
  Future<NovelReaderPreferences?> load() async => null;
}
