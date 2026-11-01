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
  wordSpacingRuby('word-spacing'),
  fontSizePolicy('font-size'),
  fontSizePolicyRuby('font-size'),
  lineHeightPolicy('line-height'),
  lineHeightPolicyRuby('line-height'),
  fontWeight('font-weight'),
  fontWeightRuby('font-weight');

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
      setting == _Setting.wordSpacingRuby ||
      setting == _Setting.fontSizePolicyRuby ||
      setting == _Setting.lineHeightPolicyRuby ||
      setting == _Setting.fontWeightRuby;
  final letters =
      setting == _Setting.letterSpacing ||
      setting == _Setting.letterSpacingRuby;
  final words =
      setting == _Setting.wordSpacing || setting == _Setting.wordSpacingRuby;
  final sizePolicy =
      setting == _Setting.fontSizePolicy ||
      setting == _Setting.fontSizePolicyRuby;
  final heightPolicy =
      setting == _Setting.lineHeightPolicy ||
      setting == _Setting.lineHeightPolicyRuby;
  final weight =
      setting == _Setting.fontWeight || setting == _Setting.fontWeightRuby;
  final extended = letters || words || sizePolicy || heightPolicy || weight;
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
          fontSize: sizePolicy || heightPolicy || weight
              ? 20
              : profileReaderPreferences.fontSize,
          typography: NovelReaderTypographyOverrides(
            firstLineIndent: setting != _Setting.indent
                ? const NovelReaderFirstLineIndent(em: 1.5)
                : null,
            paragraphSpacing: extended
                ? const NovelReaderParagraphSpacing(before: 12, after: 31)
                : null,
            letterSpacing: words || sizePolicy || heightPolicy || weight
                ? const NovelReaderLetterSpacing(logicalPixels: -1.25)
                : null,
            wordSpacing: sizePolicy || heightPolicy || weight
                ? const NovelReaderWordSpacing(logicalPixels: 7.5)
                : null,
            fontSizeScope: heightPolicy || weight
                ? NovelReaderStyleScope.forceBody
                : null,
            lineHeightScope: weight ? NovelReaderStyleScope.forceBody : null,
          ),
        ),
      );
      final baseline = await repository().load();
      final data = NovelMainPageProfileData();
      final source = data.add(
        List.generate(
          32,
          (i) =>
              '<p style="text-indent:10px${heightPolicy
                  ? ';font-size:12px;line-height:28px'
                  : sizePolicy
                  ? ';font-size:12px'
                  : weight
                  ? ';font-weight:300'
                  : ''}">Paragraph $i: '
              '${mixed ? 'before <ruby>base<rt>note</rt></ruby> after. ' : ''}'
              '${weight ? '<strong>emphasis</strong> ' : ''}'
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
            theme: extended
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

      void checkVisibleIndent(
        ProfileReaderObservation observation,
        double em, {
        double? fontSize,
      }) {
        final target = observation.nativeController!.viewForPage(
          observation.page!,
        )!;
        var checked = 0;
        void collect(Element element) {
          if (element.widget
              case ForumBodyParagraphSurface(lease: final lease, startLine: 0)
              when lease.isActive) {
            final expected =
                em * (fontSize ?? state().preferences.fontSize) +
                lease.layout.horizontalInset;
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
              closeTo(
                em * (fontSize ?? state().preferences.fontSize) +
                    view.nativeLeases
                        .whereType<ForumBodyInlineParagraphLease>()
                        .single
                        .layout
                        .horizontalInset,
                .001,
              ),
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
        double? fontSize,
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
          final resolvedSize = fontSize ?? state().preferences.fontSize;
          final character = boxes(0, 1).single;
          expect(
            character.right - character.left,
            closeTo(resolvedSize + number, .001),
          );
          if (checkSpaces) {
            final index = text.indexOf(' ');
            expect(index, greaterThan(0));
            final space = boxes(index, index + 1).single;
            expect(
              space.right - space.left,
              closeTo(resolvedSize + number + wordSpacing, .001),
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

      void checkVisibleLineHeight(
        ProfileReaderObservation observation,
        double stride,
      ) {
        final target = observation.nativeController!.viewForPage(
          observation.page!,
        )!;
        expect(target.coverage.hasClippedGlyphs, isFalse);
        void verifyVerticalCoverage(
          ForumBodyPreparedTextFragment prepared,
          String? path,
          int startLine,
        ) {
          final fragment = target.snapshot[target.pageIndex].fragments
              .firstWhere((f) => f.path == path && f.startLine == startLine);
          final top = (-fragment.top).clamp(0.0, fragment.height);
          final bottom = (target.snapshot.height - fragment.top).clamp(
            0.0,
            fragment.height,
          );
          // Prove line-height fit with actual vertical glyph bounds. The page
          // coverage flag also includes the independent horizontal edge bounds.
          for (final range in prepared.projection.graphemeRanges(
            startUtf16: fragment.coverageStartUtf16,
            endUtf16: fragment.coverageEndUtf16,
          )) {
            for (final box in prepared.glyphBoxes(
              range.startUtf16,
              range.endUtf16,
            )) {
              expect(box.top, greaterThanOrEqualTo(top - .001));
              expect(box.bottom, lessThanOrEqualTo(bottom + .001));
            }
          }
        }

        var gaps = 0;
        void verify(List<ForumBodyParagraphLine> rows) {
          for (var i = 1; i < rows.length; i++) {
            final actual = rows[i].baseline - rows[i - 1].baseline;
            // Ruby may reserve additional annotation height. It must not shrink
            // the reader's requested row spacing to fit the original page.
            expect(
              actual,
              mixed
                  ? greaterThanOrEqualTo(stride - .001)
                  : closeTo(stride, .001),
            );
            gaps++;
          }
        }

        void collect(Element element) {
          if (element.widget
              case ForumBodyParagraphSurface(
                lease: final lease,
                startLine: final start,
                endLine: final end,
              )
              when lease.isActive) {
            verifyVerticalCoverage(
              ForumBodyPreparedTextFragment.paragraph(
                lease: lease,
                startLine: start,
                endLine: end ?? lease.layout.lines.length,
              ),
              lease.content.path,
              start,
            );
            verify(lease.layout.lines);
          }
          if (element.widget
              case ForumBodyInlineParagraphSurface(view: final view)
              when view.isActive) {
            verifyVerticalCoverage(
              ForumBodyPreparedTextFragment.inline(view),
              view.content.path,
              view.startLine,
            );
            verify(
              view.nativeLeases
                  .whereType<ForumBodyInlineParagraphLease>()
                  .single
                  .layout
                  .lines,
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
        expect(gaps, greaterThan(0));
        checkVisibleLetters(
          observation,
          baseline.typography.letterSpacing!.logicalPixels,
          wordSpacing: 7.5,
          checkSpaces: true,
        );
      }

      void checkVisibleWeight(
        ProfileReaderObservation observation,
        FontWeight base,
      ) {
        final target = observation.nativeController!.viewForPage(
          observation.page!,
        )!;
        expect(target.coverage.hasClippedGlyphs, isFalse);
        var checked = 0;
        void verify(
          ForumBodyResolvedStyle style,
          List<ForumBodyParagraphRun> runs,
        ) {
          expect(style.textStyle.fontWeight, base);
          expect(runs.any((run) => run.style.strong), isTrue);
          for (final run in runs.where(
            (r) => r.style.role == ForumBodyTextRole.body,
          )) {
            expect(
              run.style.textStyle.fontWeight,
              run.style.strong
                  ? (base == FontWeight.w700
                        ? FontWeight.w900
                        : FontWeight.w400)
                  : base,
            );
          }
          checked++;
        }

        void collect(Element element) {
          if (element.widget case ForumBodyParagraphSurface(lease: final lease)
              when lease.isActive) {
            verify(lease.content.style, lease.content.runs);
          }
          if (element.widget
              case ForumBodyInlineParagraphSurface(view: final view)
              when view.isActive) {
            verify(view.content.style, view.content.runs);
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
        checkVisibleLetters(
          observation,
          -1.25,
          wordSpacing: 7.5,
          checkSpaces: true,
        );
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
          _Setting.fontSizePolicy ||
          _Setting.fontSizePolicyRuby => l10n.novelFontSizePolicyBody,
          _Setting.lineHeightPolicy ||
          _Setting.lineHeightPolicyRuby => l10n.novelLineHeightPolicyBody,
          _Setting.fontWeight ||
          _Setting.fontWeightRuby => l10n.novelFontWeightBody,
        }),
      );
      await tester.ensureVisible(bodyChoice);
      await tester.tap(bodyChoice);
      await tester.pump();
      if (weight) {
        tester
            .widget<Slider>(
              find.byKey(const Key('novel-reader-font-weight-slider')),
            )
            .onChanged!(700);
      } else if (heightPolicy) {
        tester
            .widget<Slider>(
              find.descendant(
                of: find.byKey(const Key('novel-reader-line-height-slider')),
                matching: find.byType(Slider),
              ),
            )
            .onChanged!(2.0);
      } else if (sizePolicy) {
        tester
            .widget<Slider>(
              find.descendant(
                of: find.byKey(const Key('novel-reader-font-size-slider')),
                matching: find.byType(Slider),
              ),
            )
            .onChanged!(22);
      } else if (words) {
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
        _Setting.fontSizePolicy ||
        _Setting.fontSizePolicyRuby => baseline.typography.withFontSizeScope(
          NovelReaderStyleScope.forceBody,
        ),
        _Setting.lineHeightPolicy || _Setting.lineHeightPolicyRuby =>
          baseline.typography.withLineHeightScope(
            NovelReaderStyleScope.forceBody,
          ),
        _Setting.fontWeight ||
        _Setting.fontWeightRuby => baseline.typography.withFontWeight(
          const NovelReaderFontWeight(value: 700),
        ),
      };
      final selectedFontSize = sizePolicy ? 22.0 : baseline.fontSize;
      final selectedLineHeight = heightPolicy ? 2.0 : baseline.lineHeight;
      observation = await wait(
        (value) =>
            value.ready &&
            value.complete &&
            value.paginationKey != oldKey &&
            state().persistedPreferences.typography == expectedTypography &&
            state().persistedPreferences.fontSize == selectedFontSize &&
            state().persistedPreferences.lineHeight == selectedLineHeight,
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
      if (spacing || extended) {
        checkVisibleSpacing(observation, 31);
      }
      if (weight) checkVisibleWeight(observation, FontWeight.w700);
      if (heightPolicy) checkVisibleLineHeight(observation, 40);
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
      expect(stored.fontSize, selectedFontSize);
      expect(stored.lineHeight, selectedLineHeight);
      if (sizePolicy) {
        checkVisibleLetters(
          observation,
          -1.25,
          wordSpacing: 7.5,
          checkSpaces: true,
        );
      }
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
      if (spacing || extended) {
        checkVisibleSpacing(observation, 31);
      }
      if (weight) checkVisibleWeight(observation, FontWeight.w700);
      if (heightPolicy) checkVisibleLineHeight(observation, 40);
      if (letters) checkVisibleLetters(observation, -1.25);
      if (words) {
        checkVisibleLetters(
          observation,
          -1.25,
          wordSpacing: 7.5,
          checkSpaces: true,
        );
      }
      if (sizePolicy) {
        expect(state().preferences.fontSize, 22);
        checkVisibleLetters(
          observation,
          -1.25,
          wordSpacing: 7.5,
          checkSpaces: true,
        );
      }
      await settings();
      final beforeResetKey = observation.paginationKey;
      final reset = find.byKey(Key('novel-reader-${setting.keyPrefix}-reset'));
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await closeSettings();
      observation = await wait(
        (value) =>
            value.ready &&
            value.complete &&
            state().persistedPreferences.typography == baseline.typography &&
            (!(sizePolicy || heightPolicy || weight) ||
                value.paginationKey != beforeResetKey),
      );
      expect(
        await repository().load(),
        baseline.copyWith(
          fontSize: selectedFontSize,
          lineHeight: selectedLineHeight,
        ),
      );
      if (weight) {
        expect(position(), savedPosition);
        expect(
          observation.nativeController!
              .viewForPage(observation.page!)!
              .coverage
              .locate(anchor),
          isNotNull,
        );
        checkVisibleWeight(observation, FontWeight.w300);
        checkVisibleIndent(observation, 1.5);
        checkVisibleSpacing(observation, 31);
      }
      if (heightPolicy) {
        expect(state().preferences.lineHeight, 2.0);
        expect(position(), savedPosition);
        expect(
          observation.nativeController!
              .viewForPage(observation.page!)!
              .coverage
              .locate(anchor),
          isNotNull,
        );
        checkVisibleIndent(observation, 1.5);
        checkVisibleSpacing(observation, 31);
        checkVisibleLineHeight(observation, 28);
      }
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
      if (sizePolicy) {
        expect(state().preferences.fontSize, 22);
        checkVisibleIndent(observation, 1.5, fontSize: 12);
        checkVisibleSpacing(observation, 31);
        checkVisibleLetters(
          observation,
          -1.25,
          wordSpacing: 7.5,
          checkSpaces: true,
          fontSize: 12,
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
