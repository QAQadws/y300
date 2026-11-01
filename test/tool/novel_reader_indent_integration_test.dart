import 'package:flutter/material.dart';
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

  testWidgets(
    'settings reflow keeps coverage and persists across reader owners',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesNovelReaderPreferencesRepository repository() =>
          SharedPreferencesNovelReaderPreferencesRepository(
            preferencesStore: SharedPreferencesStore(),
            legacySource: const _NoLegacy(),
          );
      await repository().save(profileReaderPreferences);
      final baseline = await repository().load();
      final data = NovelMainPageProfileData();
      final source = data.add(
        List.generate(
          32,
          (i) =>
              '<p style="text-indent:10px">Paragraph $i: '
              'Synthetic text for checking actual native reading geometry.</p>',
        ).join(),
      );
      final args = NovelReaderArgs(
        novelId: source.novelId,
        episodeId: source.episodeId,
      );
      final navigator = GlobalKey<NavigatorState>();
      var key = GlobalKey();
      Future<void> mount() => tester.pumpWidget(
        data.scope(
          MaterialApp(
            navigatorKey: navigator,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(),
          ),
          preferences: repository(),
        ),
      );
      Future<void> open() => navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => NovelReaderPage(
            key: key,
            novelId: source.novelId,
            initialEpisodeId: source.episodeId,
            nativePagination: true,
            nativeIdleScheduler: () async {},
          ),
        ),
      );
      Future<ProfileReaderObservation> wait(
        bool Function(ProfileReaderObservation) accepts,
      ) async {
        for (var i = 0; i < 400; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          if (key.currentContext case final context?) {
            final value = observeProfileReader(context, args);
            expect(value.failed, isFalse);
            if (accepts(value)) return value;
          }
        }
        throw StateError('Reader did not settle after settings change');
      }

      state() => ProviderScope.containerOf(
        key.currentContext!,
        listen: false,
      ).read(novelReaderControllerProvider(args)).value!;
      position() {
        final snapshot = state().progressSnapshot;
        return (
          snapshot.anchorNodeId,
          snapshot.anchorTextOffset,
          snapshot.anchorFormatVersion,
          snapshot.anchorTextIdentity,
        );
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

      void checkVisibleIndent(ProfileReaderObservation observation, double em) {
        final target = observation.nativeController!.viewForPage(
          observation.page!,
        )!;
        var checked = 0;
        void collect(Element element) {
          if (element.widget
              case ForumBodyParagraphSurface(lease: final lease, startLine: 0)
              when lease.isActive) {
            final expected = em * state().preferences.fontSize;
            // These are real source glyph boxes on the mounted delivery; the
            // invisible engine prefix must not become the selected character.
            expect(
              lease.layout.selectionBoxes(0, 1).single.left,
              closeTo(expected, .001),
            );
            checked++;
          }
          element.visitChildElements(collect);
        }

        void findDelivery(Element element) {
          if (element.widget.key case ObjectKey(value: final value)
              when identical(value, target)) {
            collect(element);
          } else {
            element.visitChildElements(findDelivery);
          }
        }

        key.currentContext!.visitChildElements(findDelivery);
        expect(checked, greaterThan(0));
      }

      await mount();
      var popped = open();
      var observation = await wait((value) => value.ready && value.complete);
      observation.overlay!.onRightTap!();
      observation = await wait(
        (value) => value.ready && value.businessConfirmed && value.page == 1,
      );
      final document = state().document;
      final savedPosition = position();
      final saved = state().progressSnapshot;
      final anchor = NovelReaderTextAnchor(
        episodeId: source.episodeId,
        nodeId: saved.anchorNodeId,
        textOffset: saved.anchorTextOffset,
        formatVersion: saved.anchorFormatVersion,
        textIdentity: saved.anchorTextIdentity,
      );
      expect(anchor.hasCanonicalTextOffset, isTrue);
      final oldKey = observation.paginationKey;
      final l10n = await settings();
      await tester.ensureVisible(find.text(l10n.novelIndentBody));
      await tester.tap(find.text(l10n.novelIndentBody));
      await tester.pump();
      tester
          .widget<Slider>(find.byKey(const Key('novel-reader-indent-slider')))
          .onChanged!(1.5);
      await closeSettings();
      observation = await wait(
        (value) =>
            value.ready &&
            value.complete &&
            value.paginationKey != oldKey &&
            state().persistedPreferences.typography.firstLineIndent?.em == 1.5,
      );
      expect(state().document, same(document));
      // Layout page indices/percentages may change. The canonical text position
      // must remain identical and have actual coverage in the new delivery.
      expect(position(), savedPosition);
      expect(
        observation.nativeController!
            .viewForPage(observation.page!)!
            .coverage
            .locate(anchor),
        isNotNull,
      );
      checkVisibleIndent(observation, 1.5);
      final stored = await repository().load();
      expect(
        stored.typography.firstLineIndent,
        const NovelReaderFirstLineIndent(em: 1.5),
      );
      final firstOwner = observation.nativeOwner!;
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await popped;
      expect(firstOwner.isClosed, isTrue);
      expect(firstOwner.activeCacheHandles, 0);
      expect(firstOwner.estimatedRetainedBytes, 0);

      // Tear down the provider and reconstruct both repository and reading owner.
      await tester.pumpWidget(const SizedBox.shrink());
      key = GlobalKey();
      await mount();
      popped = open();
      observation = await wait((value) => value.ready && value.complete);
      expect(observation.nativeOwner, isNot(same(firstOwner)));
      expect(state().preferences.typography, stored.typography);
      expect(position(), savedPosition);
      expect(
        observation.nativeController!
            .viewForPage(observation.page!)!
            .coverage
            .locate(anchor),
        isNotNull,
      );
      checkVisibleIndent(observation, 1.5);
      await settings();
      await tester.ensureVisible(
        find.byKey(const Key('novel-reader-indent-reset')),
      );
      await tester.tap(find.byKey(const Key('novel-reader-indent-reset')));
      await closeSettings();
      observation = await wait(
        (value) =>
            value.ready &&
            value.complete &&
            state().persistedPreferences.typography.isEmpty,
      );
      expect(await repository().load(), baseline);
      final secondOwner = observation.nativeOwner!;
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await popped;
      expect(secondOwner.isClosed, isTrue);
      expect(secondOwner.activeCacheHandles, 0);
      expect(secondOwner.estimatedRetainedBytes, 0);
      data.release(source.episodeId);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class _NoLegacy implements NovelReaderPreferencesLegacySource {
  const _NoLegacy();
  @override
  Future<NovelReaderPreferences?> load() async => null;
}
