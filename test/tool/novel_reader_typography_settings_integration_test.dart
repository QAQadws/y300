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

enum _Setting {
  indent('indent'),
  paragraphSpacing('paragraph-spacing'),
  letterSpacing('letter-spacing'),
  letterSpacingRuby('letter-spacing'),
  wordSpacing('word-spacing'),
  wordSpacingRuby('word-spacing');

  const _Setting(this.keyPrefix);
  final String keyPrefix;
}

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

  for (final setting in _Setting.values) {
    _testSettings(setting);
  }
}

void _testSettings(_Setting setting) {
  final spacing = setting == _Setting.paragraphSpacing;
  final mixed =
      setting == _Setting.letterSpacingRuby ||
      setting == _Setting.wordSpacingRuby;
  final letters =
      setting == _Setting.letterSpacing ||
      setting == _Setting.letterSpacingRuby;
  final words =
      setting == _Setting.wordSpacing || setting == _Setting.wordSpacingRuby;
  testWidgets(
    'settings reflow keeps coverage and persists across reader owners ($setting)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesNovelReaderPreferencesRepository repository() =>
          SharedPreferencesNovelReaderPreferencesRepository(
            preferencesStore: SharedPreferencesStore(),
            legacySource: const _NoLegacy(),
          );
      await repository().save(
        profileReaderPreferences.copyWith(
          typography: words
              ? const NovelReaderTypographyOverrides(
                  firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
                  paragraphSpacing: NovelReaderParagraphSpacing(
                    before: 12,
                    after: 31,
                  ),
                  letterSpacing: NovelReaderLetterSpacing(logicalPixels: -1.25),
                )
              : letters
              ? const NovelReaderTypographyOverrides(
                  firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
                  paragraphSpacing: NovelReaderParagraphSpacing(
                    before: 12,
                    after: 31,
                  ),
                )
              : spacing
              ? const NovelReaderTypographyOverrides(
                  firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
                )
              : const NovelReaderTypographyOverrides(),
        ),
      );
      final baseline = await repository().load();
      final data = NovelMainPageProfileData();
      final source = data.add(
        List.generate(
          32,
          (i) =>
              '<p style="text-indent:10px">Paragraph $i: '
              '${mixed ? 'before <ruby>base<rt>note</rt></ruby> after. ' : ''}'
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
            theme: letters || words
                ? ThemeData.light().copyWith(
                    textTheme: const TextTheme(
                      bodyMedium: TextStyle(
                        fontFamily: 'Ahem',
                        letterSpacing: .5,
                        wordSpacing: 3.25,
                      ),
                    ),
                  )
                : null,
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
        for (var i = 0; i < (mixed ? 3000 : 400); i++) {
          await tester.pump(Duration(milliseconds: mixed ? 1 : 20));
          if (mixed) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1)),
            );
          }
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
          if (element.widget
              case ForumBodyInlineParagraphSurface(view: final view)
              when view.isActive && view.startLine == 0) {
            expect(
              view.selectionBoxes(0, 1).single.left,
              closeTo(em * state().preferences.fontSize, .001),
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

      void checkVisibleSpacing(
        ProfileReaderObservation observation,
        double gap,
      ) {
        final target = observation.nativeController!.viewForPage(
          observation.page!,
        )!;
        final rectangles = <({Rect rect, String? path})>[];
        void collect(Element element) {
          if (element.widget case ForumBodyParagraphSurface(lease: final lease)
              when lease.isActive) {
            rectangles.add((
              rect: tester.getRect(find.byWidget(element.widget)),
              path: lease.content.path,
            ));
          }
          if (element.widget
              case ForumBodyInlineParagraphSurface(view: final view)
              when view.isActive) {
            rectangles.add((
              rect: tester.getRect(find.byWidget(element.widget)),
              path: view.content.path,
            ));
          }
          element.visitChildElements(collect);
        }

        void visit(Element element) {
          if (element.widget.key case ObjectKey(value: final value)
              when identical(value, target)) {
            collect(element);
          } else {
            element.visitChildElements(visit);
          }
        }

        key.currentContext!.visitChildElements(visit);
        rectangles.sort((a, b) => a.rect.top.compareTo(b.rect.top));
        expect(rectangles.length, greaterThan(1));
        var gaps = 0;
        for (var i = 1; i < rectangles.length; i++) {
          if (rectangles[i].path == rectangles[i - 1].path) continue;
          expect(
            rectangles[i].rect.top - rectangles[i - 1].rect.bottom,
            closeTo(gap, .001),
          );
          gaps++;
        }
        expect(gaps, greaterThan(0));
      }

      void checkVisibleLetters(
        ProfileReaderObservation observation,
        double number, {
        double wordSpacing = 3.25,
        bool checkSpaces = false,
      }) {
        final target = observation.nativeController!.viewForPage(
          observation.page!,
        )!;
        var checked = 0;
        void verify(
          String text,
          TextStyle style,
          List<TextBox> Function(int, int) boxes,
        ) {
          expect(text, startsWith('Paragraph'));
          expect(style.wordSpacing, wordSpacing);
          final character = boxes(0, 1).single;
          expect(
            character.right - character.left,
            closeTo(state().preferences.fontSize + number, .001),
          );
          if (checkSpaces) {
            final index = text.indexOf(' ');
            expect(index, greaterThan(0));
            final space = boxes(index, index + 1).single;
            expect(
              space.right - space.left,
              closeTo(
                state().preferences.fontSize + number + wordSpacing,
                .001,
              ),
            );
          }
          checked++;
        }

        void collect(Element element) {
          if (element.widget
              case ForumBodyParagraphSurface(lease: final lease, startLine: 0)
              when lease.isActive) {
            verify(
              lease.content.projection.text,
              lease.content.style.textStyle,
              lease.layout.selectionBoxes,
            );
          }
          if (element.widget
              case ForumBodyInlineParagraphSurface(view: final view)
              when view.isActive && view.startLine == 0) {
            verify(
              view.content.projection.display.text,
              view.content.style.textStyle,
              view.selectionBoxes,
            );
          }
          element.visitChildElements(collect);
        }

        void visit(Element element) {
          if (element.widget.key case ObjectKey(value: final value)
              when identical(value, target)) {
            collect(element);
          } else {
            element.visitChildElements(visit);
          }
        }

        key.currentContext!.visitChildElements(visit);
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
      final policy = find.byKey(
        Key('novel-reader-${setting.keyPrefix}-policy'),
      );
      final bodyChoice = find.descendant(
        of: policy,
        matching: find.text(switch (setting) {
          _Setting.indent => l10n.novelIndentBody,
          _Setting.paragraphSpacing => l10n.novelParagraphSpacingBody,
          _Setting.letterSpacing ||
          _Setting.letterSpacingRuby => l10n.novelLetterSpacingBody,
          _Setting.wordSpacing ||
          _Setting.wordSpacingRuby => l10n.novelWordSpacingBody,
        }),
      );
      await tester.ensureVisible(bodyChoice);
      await tester.tap(bodyChoice);
      await tester.pump();
      if (words) {
        tester
            .widget<Slider>(
              find.byKey(const Key('novel-reader-word-spacing-slider')),
            )
            .onChanged!(7.5);
      } else if (letters) {
        tester
            .widget<Slider>(
              find.byKey(const Key('novel-reader-letter-spacing-slider')),
            )
            .onChanged!(-1.25);
      } else if (spacing) {
        Slider slider(String key) => tester.widget<Slider>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Slider),
          ),
        );
        slider('novel-reader-paragraph-before').onChanged!(12);
        await tester.pump();
        slider('novel-reader-paragraph-after').onChanged!(31);
      } else {
        tester
            .widget<Slider>(find.byKey(const Key('novel-reader-indent-slider')))
            .onChanged!(1.5);
      }
      await closeSettings();
      final expectedTypography = switch (setting) {
        _Setting.indent => baseline.typography.withFirstLineIndent(
          const NovelReaderFirstLineIndent(em: 1.5),
        ),
        _Setting.paragraphSpacing => baseline.typography.withParagraphSpacing(
          const NovelReaderParagraphSpacing(before: 12, after: 31),
        ),
        _Setting.letterSpacing ||
        _Setting.letterSpacingRuby => baseline.typography.withLetterSpacing(
          const NovelReaderLetterSpacing(logicalPixels: -1.25),
        ),
        _Setting.wordSpacing ||
        _Setting.wordSpacingRuby => baseline.typography.withWordSpacing(
          const NovelReaderWordSpacing(logicalPixels: 7.5),
        ),
      };
      observation = await wait(
        (value) =>
            value.ready &&
            value.complete &&
            value.paginationKey != oldKey &&
            state().persistedPreferences.typography == expectedTypography,
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
      if (spacing || letters || words) checkVisibleSpacing(observation, 31);
      if (letters) checkVisibleLetters(observation, -1.25);
      if (words) {
        checkVisibleLetters(
          observation,
          -1.25,
          wordSpacing: 7.5,
          checkSpaces: true,
        );
      }
      final stored = await repository().load();
      expect(stored.typography, expectedTypography);
      if (spacing) {
        expect(
          stored.typography.paragraphSpacing,
          const NovelReaderParagraphSpacing(before: 12, after: 31),
        );
      }
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
      if (spacing || letters || words) checkVisibleSpacing(observation, 31);
      if (letters) checkVisibleLetters(observation, -1.25);
      if (words) {
        checkVisibleLetters(
          observation,
          -1.25,
          wordSpacing: 7.5,
          checkSpaces: true,
        );
      }
      await settings();
      final reset = find.byKey(Key('novel-reader-${setting.keyPrefix}-reset'));
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await closeSettings();
      observation = await wait(
        (value) =>
            value.ready &&
            value.complete &&
            state().persistedPreferences.typography == baseline.typography,
      );
      expect(await repository().load(), baseline);
      if (spacing) {
        checkVisibleSpacing(observation, 10);
        checkVisibleIndent(observation, 1.5);
      }
      if (letters) {
        checkVisibleIndent(observation, 1.5);
        checkVisibleSpacing(observation, 31);
        checkVisibleLetters(observation, .5);
      }
      if (words) {
        checkVisibleIndent(observation, 1.5);
        checkVisibleSpacing(observation, 31);
        checkVisibleLetters(
          observation,
          -1.25,
          wordSpacing: 3.25,
          checkSpaces: true,
        );
      }
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
