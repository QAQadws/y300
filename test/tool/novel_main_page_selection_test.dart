import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_overlay_scaffold.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_flow_host.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';

import '../../tool/novel_main_page_profile_data.dart';
import '../../tool/novel_main_page_profile_observation.dart';
import '../../tool/novel_pagination_profile_fixtures.dart';

final class _Writer implements ClipboardTextWriter {
  final writes = <String>[];
  @override
  Future<void> writeText(String text) async {
    writes.add(text);
  }
}

final class _SelectionPreferences implements NovelReaderPreferencesRepository {
  _SelectionPreferences(NovelReaderFlowMode mode)
    : value = profileReaderPreferences.copyWith(
        flowMode: mode,
        typography: const NovelReaderTypographyOverrides(
          letterSpacing: NovelReaderLetterSpacing(logicalPixels: 1),
          textAlignment: NovelReaderTextAlignment(
            mode: NovelReaderTextAlignMode.justify,
          ),
        ),
      );

  NovelReaderPreferences value;

  @override
  Future<NovelReaderPreferences> load() async => value;

  @override
  Future<void> save(NovelReaderPreferences preferences) async =>
      value = preferences;
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
  testWidgets(
    'actual book and vertical readers select in place and retire stale actions',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final writer = _Writer();
      final data = NovelMainPageProfileData();
      final id = data.add(
        '<p>before <ruby>BASE<rt>NOTE</rt></ruby> after.</p>'
        '<div class="blockcode"><ol><li>  code(); </li></ol></div>'
        '<p>script <sup>UP</sup> and <sub>DOWN</sub>.</p>'
        '<table><tr><td>Adjacent page</td></tr></table><p>Last page</p>',
      );
      final args = NovelReaderArgs(
        novelId: id.novelId,
        episodeId: id.episodeId,
      );
      final navigator = GlobalKey<NavigatorState>();
      final reader = GlobalKey();
      final io = data.scope(
        MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(),
        ),
      ) as ProviderScope;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...io.overrides,
            clipboardTextWriterProvider.overrideWithValue(writer),
          ],
          child: io.child,
        ),
      );
      final route = MaterialPageRoute<void>(
        builder: (_) => NovelReaderPage(
          key: reader,
          novelId: args.novelId,
          initialEpisodeId: args.episodeId,
          nativePagination: true,
          nativeIdleScheduler: () async {},
        ),
      );
      navigator.currentState!.push(route);
      Future<void> waitUntil(bool Function() done) async {
        for (var i = 0; i < 2000; i++) {
          await tester.pump(const Duration(milliseconds: 5));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          if (done()) return;
        }
        fail('Reader selection did not reach the expected state');
      }

      ProfileReaderObservation observe() =>
          observeProfileReader(reader.currentContext!, args);
      Future<void> ready() => waitUntil(
        () =>
            reader.currentContext != null &&
            observe().ready &&
            observe().complete,
      );
      Future<void> longPressInline(
        String text, {
        bool annotation = false,
      }) async {
        final observation = observe();
        final target = observation.page == null
            ? null
            : observation.nativeController?.viewForPage(observation.page!);
        if (target == null) await tester.pumpAndSettle();
        ForumBodyInlineParagraphSurface? surface;
        void collect(Element e) {
          if (e.widget case final ForumBodyInlineParagraphSurface w
              when w.view.isActive &&
                  w.view.content.contexts.any(
                    (c) => c.content.projection.text == text,
                  )) {
            surface = w;
            return;
          }
          e.visitChildElements(collect);
        }

        void findTarget(Element e) {
          if (target == null && e.widget is NovelReaderNativeFlowHost) {
            collect(e);
          } else if (e.widget.key case ObjectKey(value: final value)
              when identical(value, target)) {
            collect(e);
          } else {
            e.visitChildElements(findTarget);
          }
        }

        findTarget(reader.currentContext! as Element);
        final w = surface!;
        final context = w.view.content.contexts.firstWhere(
          (c) => c.content.projection.text == text,
        );
        final box = w.view
            .glyphBoxes(context.startUtf16, context.startUtf16 + 1)
            .first;
        await tester.longPressAt(
          tester.getTopLeft(find.byWidget(w)) +
              Offset(
                box.left + (box.right - box.left) * .25,
                (box.top + box.bottom) * .5,
              ),
        );
        final targetFinder = annotation
            ? find.byKey(const Key('novel-native-selection-copy-page'))
            : find.byType(AdaptiveTextSelectionToolbar);
        if (target == null) {
          final scope = tester.state<ForumBodyFlowSelectionScopeState>(
            find.byType(ForumBodyFlowSelectionScope),
          );
          expect(scope.selectedText, text);
        }
        await waitUntil(() => targetFinder.evaluate().isNotEmpty);
      }

      ForumContentSelectionCopyPage selection() =>
          tester.widget(find.byType(ForumContentSelectionCopyPage));
      VoidCallback copyButton() => tester
          .widget<AdaptiveTextSelectionToolbar>(
            find.byType(AdaptiveTextSelectionToolbar),
          )
          .buttonItems!
          .singleWhere((b) => b.type == ContextMenuButtonType.copy)
          .onPressed!;
      Future<VoidCallback> selectAll() async {
        final copyPage = find.byType(ForumContentSelectionCopyPage);
        final region = tester.state<SelectableRegionState>(
          copyPage.evaluate().isEmpty
              ? find.byType(SelectableRegion)
              : find.descendant(
                  of: copyPage,
                  matching: find.byType(SelectableRegion),
                ),
        );
        region.selectAll(SelectionChangedCause.toolbar);
        await tester.pumpAndSettle();
        return copyButton();
      }

      try {
        await ready();
        final owner = observe().nativeOwner!;
        expect(observe().count, greaterThan(1));
        final originalPage = observe().page;
        final l10n = AppLocalizations.of(reader.currentContext!);
        await longPressInline('BASE');
        expect(find.byType(ForumContentSelectionCopyPage), findsNothing);
        copyButton()();
        await tester.pumpAndSettle();
        expect(writer.writes, ['BASE']);
        final stale = await selectAll();
        final c = ProviderScope.containerOf(
          reader.currentContext!,
          listen: false,
        );
        final previousLayout = observe().paginationKey;
        final state = c.read(novelReaderControllerProvider(args)).requireValue;
        c
            .read(novelReaderControllerProvider(args).notifier)
            .previewPreferences(state.preferences.copyWith(fontSize: 22));
        await waitUntil(
          () => observe().ready && observe().paginationKey != previousLayout,
        );
        stale();
        await tester.pumpAndSettle();
        expect(writer.writes, ['BASE']);
        await ready();
        expect(observe().page, originalPage);

        await longPressInline('NOTE', annotation: true);
        expect(selection().title, l10n.novelAnnotationSelectionCopyTitle);
        expect(selection().isCurrent!(), isTrue);
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('novel-native-selection-copy-text')),
              )
              .data,
          'NOTE',
        );
        (await selectAll())();
        await tester.pumpAndSettle();
        expect(writer.writes, ['BASE', 'NOTE']);
        navigator.currentState!.pop();
        await ready();

        for (final text in ['UP', 'DOWN']) {
          await longPressInline(text);
          expect(find.byType(ForumContentSelectionCopyPage), findsNothing);
          if (text == 'DOWN') {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          } else {
            copyButton()();
          }
          await tester.pumpAndSettle();
          expect(writer.writes.last, text);
        }

        final codeFinder = find.byWidgetPredicate(
          (w) =>
              w is ForumBodyParagraphSurface &&
              w.lease.isActive &&
              w.lease.content.projection.text == '  code(); ',
        );
        final code = tester.widget<ForumBodyParagraphSurface>(codeFinder);
        final box = code.lease.layout.selectionBoxes(2, 3).first;
        await tester.longPressAt(
          tester.getTopLeft(codeFinder) +
              Offset(
                box.left + (box.right - box.left) * .25,
                (box.top + box.bottom) * .5,
              ),
        );
        await waitUntil(
          () => find.byType(AdaptiveTextSelectionToolbar).evaluate().isNotEmpty,
        );
        expect(find.byType(ForumContentSelectionCopyPage), findsNothing);
        (await selectAll())();
        await tester.pumpAndSettle();
        expect(writer.writes, [
          'BASE',
          'NOTE',
          'UP',
          'DOWN',
          'before BASE after.\n  code(); \nscript UP and DOWN.',
        ]);
        final controller = c.read(novelReaderControllerProvider(args).notifier);
        controller.previewPreferences(
          c
              .read(novelReaderControllerProvider(args))
              .requireValue
              .preferences
              .copyWith(flowMode: NovelReaderFlowMode.vertical),
        );
        final flow = find.byType(NovelReaderNativeFlowHost);
        await waitUntil(
          () =>
              flow.evaluate().isNotEmpty &&
              tester
                  .state<NovelReaderNativeFlowHostState>(flow)
                  .isSelectionCurrent &&
              find
                  .byType(ForumBodyInlineParagraphSurface)
                  .evaluate()
                  .isNotEmpty,
        );
        await longPressInline('BASE');
        expect(find.byType(ForumContentSelectionCopyPage), findsNothing);
        copyButton()();
        await tester.pumpAndSettle();
        expect(writer.writes.last, 'BASE');
        final retired = await selectAll();
        navigator.currentState!.removeRoute(route);
        await tester.pumpAndSettle();
        retired();
        await tester.pumpAndSettle();
        expect(writer.writes, hasLength(6));
        expect(owner.isClosed, isTrue);
        expect(owner.activeCacheHandles, 0);
        expect(owner.retainedCacheGenerations, 0);
        expect(owner.estimatedRetainedBytes, 0);
        data.release(args.episodeId);
        expect(data.retainedChapters, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  for (final (mode, reverse) in [
    (NovelReaderFlowMode.pagedLtr, false),
    (NovelReaderFlowMode.pagedRtl, true),
    (NovelReaderFlowMode.vertical, true),
  ]) {
    testWidgets('logical selection spans evicted content in ${mode.name}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final writer = _Writer();
      final lines = [
        'Alpha',
        novelProfileBasicWrapWord,
        for (var index = 0; index < 55; index++) '段落$index${'正文内容' * 20}',
        novelProfileBasicWrapUrl,
        'Omega',
      ];
      final data = NovelMainPageProfileData();
      final id = data.add(
        lines.map((line) {
          if (line == novelProfileBasicWrapUrl) {
            return '<p lang="en"><a href="$line">$line</a></p>';
          }
          if (line == novelProfileBasicWrapWord) {
            return '<p lang="en">$line</p>';
          }
          return '<p>$line</p>';
        }).join(),
      );
      final args = NovelReaderArgs(
        novelId: id.novelId,
        episodeId: id.episodeId,
      );
      final reader = GlobalKey();
      final scoped = data.scope(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NovelReaderPage(
            key: reader,
            novelId: id.novelId,
            initialEpisodeId: id.episodeId,
            nativePagination: true,
            nativeIdleScheduler: () async {},
          ),
        ),
        preferences: _SelectionPreferences(mode),
      ) as ProviderScope;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...scoped.overrides,
            clipboardTextWriterProvider.overrideWithValue(writer),
          ],
          child: scoped.child,
        ),
      );

      final vertical = mode == NovelReaderFlowMode.vertical;
      final flow = find.byType(ForumBodyFlowSliver);
      final flowHost = find.byType(NovelReaderNativeFlowHost);
      final controls = find.byKey(
        const Key('novel-logical-selection-controls'),
      );
      final l10n = AppLocalizations.of(reader.currentContext!);
      ProfileReaderObservation book() =>
          observeProfileReader(reader.currentContext!, args);
      ForumBodyFlowSliver sliver() => tester.widget<ForumBodyFlowSliver>(flow);
      final viewports = find.byType(ForumBodyTextPageSurface);

      Future<void> waitUntil(bool Function() ready) async {
        for (var frame = 0; frame < 240; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump(const Duration(milliseconds: 10));
          if (ready()) return;
        }
        fail('Reader did not reach the requested selection state');
      }

      bool ready() => vertical
          ? flow.evaluate().isNotEmpty &&
                sliver().prefix.isComplete &&
                viewports.evaluate().isNotEmpty
          : book().ready && book().complete;

      Iterable<Offset> glyphs(ForumBodySourceRange range) sync* {
        for (final element in viewports.evaluate()) {
          final page = element.widget as ForumBodyTextPageSurface;
          final box = element.findRenderObject()! as RenderBox;
          for (final rect in page.locateSourceRanges([range])) {
            yield box.localToGlobal(rect.center);
          }
        }
      }

      Future<void> goToEdge(bool tail) async {
        if (vertical) {
          final scroll = tester
              .widget<NovelReaderNativeFlowHost>(flowHost)
              .scrollController;
          scroll.jumpTo(tail ? scroll.position.maxScrollExtent : 0);
          await tester.pumpAndSettle();
        } else {
          final current = book();
          final page = tail ? current.count - 1 : 0;
          if (page != current.page) {
            expect(current.nativeController!.requestPage(page), isTrue);
            await waitUntil(() => book().ready && book().page == page);
          }
        }
      }

      Future<void> mark(ForumBodySourceRange source, String action) async {
        final bounds = tester.getRect(find.byType(Scaffold).first);
        await waitUntil(() => glyphs(source).any(bounds.contains));
        await tester.pumpAndSettle();
        await tester.longPressAt(glyphs(source).firstWhere(bounds.contains));
        final toolbar = find.byType(AdaptiveTextSelectionToolbar);
        await waitUntil(() => toolbar.evaluate().isNotEmpty);
        final item = tester
            .widget<AdaptiveTextSelectionToolbar>(toolbar.last)
            .buttonItems!
            .singleWhere((item) => item.label == action);
        item.onPressed!();
        await tester.pumpAndSettle();
      }

      try {
        await waitUntil(ready);
        await tester.pumpAndSettle();
        final owner = vertical
            ? tester.widget<NovelReaderNativeFlowHost>(flowHost).owner
            : book().nativeOwner!;
        final identity = vertical
            ? sliver().prefix.identity
            : book().nativeController!.snapshot!.identity;
        final length = lines.join().runes.length;
        final head = ForumBodySourceRange(identity, 0, 1);
        final tail = ForumBodySourceRange(identity, length - 1, length);
        final wordStart = lines.first.length;
        final wordRange = ForumBodySourceRange(
          identity,
          wordStart,
          wordStart + novelProfileBasicWrapWord.length,
        );
        final urlEnd = length - lines.last.length;
        final urlRange = ForumBodySourceRange(
          identity,
          urlEnd - novelProfileBasicWrapUrl.length,
          urlEnd,
        );
        final start = reverse ? tail : head;
        final end = reverse ? head : tail;
        await goToEdge(reverse);
        expect(
          glyphs(reverse ? urlRange : wordRange).map((p) => p.dy).toSet(),
          hasLength(greaterThan(1)),
        );
        await mark(start, l10n.novelSelectionStart);
        expect(find.text(l10n.novelSelectionChooseEnd), findsOneWidget);

        final overlay = tester
            .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
            .controller!;
        overlay.showMenu();
        await tester.pumpAndSettle();
        expect(controls, findsNothing);
        overlay.hideMenu();
        await waitUntil(() => ready() && controls.evaluate().isNotEmpty);

        await goToEdge(!reverse);
        expect(glyphs(start), isEmpty);
        expect(
          glyphs(reverse ? wordRange : urlRange).map((p) => p.dy).toSet(),
          hasLength(greaterThan(1)),
        );
        await mark(end, l10n.novelSelectionEnd);
        final selected = ForumBodySourceRange(identity, 0, length);
        expect(
          tester
              .widgetList<ForumBodyTextHighlight>(
                find.byType(ForumBodyTextHighlight),
              )
              .any((mark) => mark.ranges.contains(selected)),
          isTrue,
        );
        expect(glyphs(selected), isNotEmpty);
        final copy = find.widgetWithText(TextButton, l10n.novelSelectionCopy);
        await tester.tap(copy);
        await waitUntil(() => writer.writes.isNotEmpty);
        await tester.pumpAndSettle();
        expect(writer.writes, [lines.join('\n')]);
        expect(controls, findsNothing);

        await mark(end, l10n.novelSelectionStart);
        if (vertical) {
          await tester.tap(find.byTooltip(l10n.novelSelectionClear));
          await tester.pumpAndSettle();
          expect(controls, findsNothing);
          await mark(end, l10n.novelSelectionStart);
        }
        await mark(end, l10n.novelSelectionEnd);
        final stale = tester.widget<TextButton>(copy).onPressed!;
        Object? layout() =>
            vertical ? sliver().session : book().nativeController;
        final previous = layout();
        if (vertical) {
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.binding.setSurfaceSize(const Size(720, 600));
        } else {
          final provider = novelReaderControllerProvider(args);
          final container = ProviderScope.containerOf(
            reader.currentContext!,
            listen: false,
          );
          container
              .read(provider.notifier)
              .previewPreferences(
                container
                    .read(provider)
                    .requireValue
                    .preferences
                    .copyWith(fontSize: 23),
              );
        }
        await tester.pump();
        await waitUntil(
          () =>
              ready() &&
              !identical(previous, layout()) &&
              controls.evaluate().isEmpty,
        );
        stale();
        await tester.pumpAndSettle();
        expect(writer.writes, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(owner.isClosed, isTrue);
        expect(owner.activeCacheHandles, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }
}
