import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_flow_host.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_surface.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../tool/novel_main_page_profile_data.dart';
import '../../tool/novel_main_page_profile_observation.dart';

void main() {
  for (final mode in [
    NovelReaderFlowMode.pagedLtr,
    NovelReaderFlowMode.vertical,
  ]) {
    testWidgets('blank line switch reuses converted sources in ${mode.name}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel('flutter_open_chinese_convert');
      final messenger = tester.binding.defaultBinaryMessenger;
      var conversionCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        conversionCalls++;
        return ((call.arguments as List<Object?>).first as String).replaceAll(
          '台词',
          '臺詞',
        );
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      SharedPreferencesNovelReaderPreferencesRepository repository() =>
          SharedPreferencesNovelReaderPreferencesRepository(
            preferencesStore: SharedPreferencesStore(),
            legacySource: const _NoLegacy(),
          );
      final preferences = repository();
      await preferences.save(
        profileReaderPreferences.copyWith(
          flowMode: mode,
          conversionMode: NovelReaderConversionMode.toTraditional,
        ),
      );
      final data = NovelMainPageProfileData();
      final chapter = data.add(
        '<p>台词<br><br><br><br>句尾</p>'
        '<p>&nbsp;</p><p>　</p><p>下一段</p>',
      );
      final args = NovelReaderArgs(
        novelId: chapter.novelId,
        episodeId: chapter.episodeId,
      );
      final readerKey = GlobalKey();
      final executor = _ChapterExecutor();
      final writer = _Writer();
      final fixture = data.scope(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NovelReaderPage(
            key: readerKey,
            novelId: chapter.novelId,
            initialEpisodeId: chapter.episodeId,
            nativePagination: true,
            nativeIdleScheduler: () async {},
          ),
        ),
        preferences: preferences,
      ) as ProviderScope;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...fixture.overrides,
            novelReaderNativePreparationServiceProvider.overrideWith(
              (ref) => DefaultNovelReaderNativePreparationService(
                executor: executor,
                conversionService: ref.watch(
                  htmlTextNodeConversionServiceProvider,
                ),
              ),
            ),
            clipboardTextWriterProvider.overrideWithValue(writer),
          ],
          child: fixture.child,
        ),
      );

      final sliver = find.byType(ForumBodyFlowSliver);
      final provider = novelReaderControllerProvider(args);
      final scope = ProviderScope.containerOf(
        readerKey.currentContext!,
        listen: false,
      );
      ProfileReaderObservation observe() =>
          observeProfileReader(readerKey.currentContext!, args);
      bool layoutReady() => mode == NovelReaderFlowMode.vertical
          ? sliver.evaluate().isNotEmpty &&
                tester.widget<ForumBodyFlowSliver>(sliver).prefix.isComplete
          : observe().ready && observe().complete;
      Iterable<String> text() => tester
          .widgetList<ForumBodyParagraphSurface>(
            find.byType(ForumBodyParagraphSurface),
          )
          .where((surface) => surface.lease.isActive)
          .map((surface) => surface.lease.content.projection.text);
      ReaderOverlayController overlay() => tester
          .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
          .controller!;
      Future<void> wait(bool Function() predicate) async {
        for (var frame = 0; frame < 300; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          expect(
            observe().failed,
            isFalse,
            reason:
                '${scope.read(provider).error}\n${scope.read(provider).stackTrace}',
          );
          if (predicate()) return;
        }
        fail('Reader did not settle for blank line cleanup. Text: ${text()}');
      }

      Future<void> toggle({required bool from}) async {
        overlay().showMenu();
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('shared-reader-bottom-action-display')),
        );
        await tester.pumpAndSettle();
        final sheet = find.byKey(
          const Key('novel-reader-display-settings-sheet'),
        );
        final context = tester.element(sheet);
        final label = AppLocalizations.of(context).novelCompressBlankLines;
        final control = find.widgetWithText(SwitchListTile, label);
        await tester.ensureVisible(control);
        expect(tester.widget<SwitchListTile>(control).value, from);
        await tester.tap(control);
        await tester.pump();
        expect(tester.widget<SwitchListTile>(control).value, !from);
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
      }

      try {
        await wait(() => layoutReady() && text().contains('　'));
        final document = scope.read(provider).requireValue.document;
        expect(document.textConversionIdentity, 'toTraditional');
        expect(text(), contains('臺詞\n'));
        expect(text().where((value) => value == '\n'), hasLength(3));
        final initialConversionCalls = conversionCalls;
        expect(initialConversionCalls, greaterThan(0));
        expect(executor.calls, 1);

        await toggle(from: false);
        await wait(() => layoutReady() && !text().contains('　'));
        expect(text().where((value) => value == '\n'), hasLength(1));
        expect(text(), containsAll(['臺詞\n', '句尾', '\u00a0', '下一段']));
        expect((await repository().load()).compressBlankLines, isTrue);
        expect(scope.read(provider).requireValue.document, same(document));
        expect(conversionCalls, initialConversionCalls);
        expect(executor.calls, 1);

        final region = tester.state<SelectableRegionState>(
          find.byType(SelectableRegion),
        );
        region.selectAll(SelectionChangedCause.toolbar);
        await tester.pumpAndSettle();
        final toolbar = tester.widget<AdaptiveTextSelectionToolbar>(
          find.byType(AdaptiveTextSelectionToolbar),
        );
        toolbar.buttonItems!
            .singleWhere((item) => item.type == ContextMenuButtonType.copy)
            .onPressed!();
        await tester.pumpAndSettle();
        expect(writer.writes, ['臺詞\n句尾\n\u00a0\n下一段']);

        overlay().showMenu();
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('shared-reader-top-action-search-text')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('novel-reader-text-search-field')),
          '句尾',
        );
        await tester.pump();
        await tester.tap(
          find.byTooltip(
            AppLocalizations.of(readerKey.currentContext!).commonSearch,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.textContaining('句尾'),
          ),
        );
        List<ForumBodySourceRange> highlight() => tester
            .widgetList<ForumBodyTextHighlight>(
              find.byType(ForumBodyTextHighlight),
            )
            .expand((mark) => mark.ranges)
            .toSet()
            .toList();
        bool painted() => tester
            .widgetList<ForumBodyTextPageSurface>(
              find.byType(ForumBodyTextPageSurface),
            )
            .any((page) => page.locateSourceRanges(highlight()).isNotEmpty);
        bool navigationSettled() {
          if (overlay().contentObscured.value || !layoutReady()) return false;
          final request = mode == NovelReaderFlowMode.vertical
              ? tester
                    .widget<NovelReaderNativeFlowHost>(
                      find.byType(NovelReaderNativeFlowHost),
                    )
                    .navigationRequest
              : tester
                    .widget<NovelReaderNativePagedSurface>(
                      find.byType(NovelReaderNativePagedSurface),
                    )
                    .navigationRequest;
          return request == null && painted();
        }

        await wait(navigationSettled);
        final selected = highlight().single;
        expect(selected.endRune - selected.startRune, 2);

        await toggle(from: true);
        await wait(() => layoutReady() && text().contains('　'));
        expect(highlight(), [selected]);
        expect(painted(), isTrue);
        expect(text().where((value) => value == '\n'), hasLength(3));
        expect((await repository().load()).compressBlankLines, isFalse);
        expect(scope.read(provider).requireValue.document, same(document));
        expect(conversionCalls, initialConversionCalls);
        expect(executor.calls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }
}

final class _ChapterExecutor implements NovelReaderNativeChapterBuildExecutor {
  int calls = 0;

  @override
  Future<NovelReaderNativeChapterPreparation> build(
    NovelReaderNativeChapterBuildRequest request,
  ) {
    calls++;
    return const AdaptiveNovelReaderNativeChapterBuildExecutor().build(request);
  }
}

final class _Writer implements ClipboardTextWriter {
  final writes = <String>[];

  @override
  Future<void> writeText(String text) async => writes.add(text);
}

final class _NoLegacy implements NovelReaderPreferencesLegacySource {
  const _NoLegacy();

  @override
  Future<NovelReaderPreferences?> load() async => null;
}
