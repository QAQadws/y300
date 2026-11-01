import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
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
      'custom colors preserve author paint, canonical coverage and saved state across owners (ruby=$mixed)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesNovelReaderPreferencesRepository repository() =>
            SharedPreferencesNovelReaderPreferencesRepository(
              preferencesStore: SharedPreferencesStore(),
              legacySource: const _NoLegacy(),
            );
        final initial = profileReaderPreferences.copyWith(
          fontSize: 20,
          typography: const NovelReaderTypographyOverrides(
            firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
            wordSpacing: NovelReaderWordSpacing(logicalPixels: 3),
          ),
          viewport: const NovelReaderViewportOverrides(left: 12, right: 20),
        );
        await repository().save(initial);
        final data = NovelMainPageProfileData();
        final source = data.add(
          List.generate(
            24,
            (i) =>
                '<p>Body $i '
                '<span style="color:#b22222;background-color:#ffe000">Author highlight</span> '
                '<a href="https://example.invalid/synthetic">Link</a> '
                '${mixed ? 'before <ruby>base<rt>note</rt></ruby> after ' : ''}'
                'Synthetic custom color settings preserve reading position and actual native coverage.</p>',
          ).join(),
        );
        final args = NovelReaderArgs(
          novelId: source.novelId,
          episodeId: source.episodeId,
        );
        final navigator = GlobalKey<NavigatorState>();
        var readerKey = GlobalKey();
        final canvasKey = GlobalKey();
        await tester.pumpWidget(
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
              home: const Scaffold(),
            ),
            preferences: repository(),
          ),
        );
        Future<void> open() => navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => RepaintBoundary(
              key: canvasKey,
              child: NovelReaderPage(
                key: readerKey,
                novelId: source.novelId,
                initialEpisodeId: source.episodeId,
                nativePagination: true,
                nativeIdleScheduler: () async {},
              ),
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
          throw StateError('Color settings did not settle');
        }

        Future<void> settings() async {
          await tester.tapAt(const Offset(400, 300));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('shared-reader-bottom-action-display')),
          );
          await tester.pumpAndSettle();
        }

        Future<void> closeSettings() async {
          Navigator.of(
            tester.element(
              find.byKey(const Key('novel-reader-display-settings-sheet')),
            ),
          ).pop();
          await tester.pumpAndSettle();
        }

        Future<void> choose(String part, String rgb) async {
          final edit = find.byKey(Key('novel-reader-$part-edit'));
          await tester.ensureVisible(edit);
          await tester.tap(edit);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('novel-reader-color-input')),
            rgb,
          );
          await tester.pump();
          await tester.tap(find.byKey(const Key('novel-reader-color-apply')));
          await tester.pumpAndSettle();
        }

        Future<void> reset(String part) async {
          final button = find.byKey(Key('novel-reader-$part-reset'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pump();
        }

        var popped = open();
        var observation = await wait((o) => o.ready && o.complete);
        observation.overlay!.onRightTap!();
        observation = await wait(
          (o) => o.ready && o.businessConfirmed && o.page == 1,
        );
        final savedPosition = position();
        final p = state().progressSnapshot;
        final anchor = NovelReaderTextAnchor(
          episodeId: source.episodeId,
          nodeId: p.anchorNodeId,
          textOffset: p.anchorTextOffset,
          formatVersion: p.anchorFormatVersion,
          textIdentity: p.anchorTextIdentity,
        );
        var document = state().document;
        final firstOwner = observation.nativeOwner!;
        void accepted(
          ProfileReaderObservation o,
          NovelReaderColorOverrides expected,
        ) {
          expect(state().document, same(document));
          expect(state().preferences.colors, expected);
          expect(state().preferences.typography, initial.typography);
          expect(state().preferences.viewport, initial.viewport);
          expect(position(), savedPosition);
          final page = o.nativeController!.viewForPage(o.page!)!;
          expect(page.coverage.hasClippedGlyphs, false);
          expect(page.coverage.locate(anchor), isNotNull);
          final palette = const NovelReaderThemeResolver().resolve(
            preferences: state().preferences,
            theme: Theme.of(
              tester.element(find.byType(NovelReaderNativePagedSurface)),
            ),
          );
          final runs = [
            for (final element
                in find.byType(ForumBodyParagraphSurface).evaluate())
              ...(element.widget as ForumBodyParagraphSurface)
                  .lease
                  .content
                  .runs,
            for (final element
                in find.byType(ForumBodyInlineParagraphSurface).evaluate())
              ...(element.widget as ForumBodyInlineParagraphSurface)
                  .view
                  .content
                  .runs,
          ];
          expect(
            runs.map((r) => r.style.textStyle.color),
            contains(palette.foreground),
          );
          expect(
            runs.map((r) => r.style.textStyle.color),
            contains(const Color(0xffb22222)),
          );
          expect(
            runs.map((r) => r.style.textStyle.backgroundColor),
            contains(const Color(0xffffe000)),
          );
          expect(
            runs
                .where((r) => r.style.linkTarget != null)
                .map((r) => r.style.textStyle.color),
            contains(palette.link),
          );
        }

        await settings();
        await choose('foreground', '#203040');
        await choose('background', '#E8F0D8');
        await closeSettings();
        const selected = NovelReaderColorOverrides(
          foreground: 0x203040,
          background: 0xe8f0d8,
        );
        observation = await wait(
          (o) =>
              o.ready &&
              o.complete &&
              state().persistedPreferences.colors == selected,
        );
        accepted(observation, selected);
        // Validate actual raster paint, not just the palette/style metadata.
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(canvasKey),
        );
        final image = (await tester.runAsync(
          () => boundary.toImage(pixelRatio: 1),
        ))!;
        try {
          final pixels = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          ))!;
          final rgb = <int>{};
          final body = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
          final origin = tester.getTopLeft(find.byKey(canvasKey));
          for (
            var y = (body.top - origin.dy).ceil();
            y < (body.bottom - origin.dy).floor();
            y++
          ) {
            for (
              var x = (body.left - origin.dx).ceil();
              x < (body.right - origin.dx).floor();
              x++
            ) {
              final i = (y * image.width + x) * 4;
              rgb.add(
                (pixels.getUint8(i) << 16) |
                    (pixels.getUint8(i + 1) << 8) |
                    pixels.getUint8(i + 2),
              );
            }
          }
          expect(rgb, containsAll([0x203040, 0xe8f0d8, 0xb22222, 0xffe000]));
        } finally {
          image.dispose();
        }
        await settings();
        await reset('foreground');
        await closeSettings();
        observation = await wait(
          (o) =>
              o.ready &&
              o.complete &&
              state().persistedPreferences.colors ==
                  selected.withForeground(null),
        );
        accepted(observation, selected.withForeground(null));
        await settings();
        await choose('foreground', '#203040');
        await closeSettings();
        observation = await wait(
          (o) =>
              o.ready &&
              o.complete &&
              state().persistedPreferences.colors == selected,
        );
        accepted(observation, selected);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await popped;
        expect(firstOwner.isClosed, true);
        expect(firstOwner.activeCacheHandles, 0);
        expect(firstOwner.estimatedRetainedBytes, 0);
        readerKey = GlobalKey();
        popped = open();
        observation = await wait((o) => o.ready && o.complete);
        expect(observation.nativeOwner, isNot(same(firstOwner)));
        document = state().document;
        accepted(observation, selected);
        await settings();
        await reset('background');
        await closeSettings();
        observation = await wait(
          (o) =>
              o.ready &&
              o.complete &&
              state().persistedPreferences.colors ==
                  selected.withBackground(null),
        );
        accepted(observation, selected.withBackground(null));
        final stored = await repository().load();
        expect(stored.colors, selected.withBackground(null));
        expect(stored.typography, initial.typography);
        expect(stored.viewport, initial.viewport);
        final lastOwner = observation.nativeOwner!;
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await popped;
        expect(lastOwner.isClosed, true);
        expect(lastOwner.activeCacheHandles, 0);
        expect(lastOwner.estimatedRetainedBytes, 0);
        data.release(source.episodeId);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _NoLegacy implements NovelReaderPreferencesLegacySource {
  const _NoLegacy();
  @override
  Future<NovelReaderPreferences?> load() async => null;
}
