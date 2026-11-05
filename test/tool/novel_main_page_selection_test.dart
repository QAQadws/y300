import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';

import '../../tool/novel_main_page_profile_data.dart';
import '../../tool/novel_main_page_profile_observation.dart';

final class _Writer implements ClipboardTextWriter {
  final writes = <String>[];
  @override
  Future<void> writeText(String text) async {
    writes.add(text);
  }
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
    'actual reader selects in place, copies explicit annotation and retires stale actions',
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
        final target = observe().nativeController!.viewForPage(
          observe().page!,
        )!;
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
          if (e.widget.key case ObjectKey(value: final value)
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
        final retired = await selectAll();
        navigator.currentState!.removeRoute(route);
        await tester.pumpAndSettle();
        retired();
        await tester.pumpAndSettle();
        expect(writer.writes, hasLength(5));
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
}
