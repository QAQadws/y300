import '../../tool/legacy/novel/legacy_reader_surface.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/navigation/forum_link_routes.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_delayed_loading_boundary.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_surface.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../tool/novel_main_page_profile_data.dart';
import '../../tool/novel_main_page_profile_observation.dart';

void main() {
  for (final mode in [
    NovelReaderFlowMode.pagedLtr,
    NovelReaderFlowMode.vertical,
  ]) {
    testWidgets(
      'actual native reader opens tapped and selected links in ${mode.name}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final writer = _Writer();
        final data = NovelMainPageProfileData();
        const textUrl = 'https://example.invalid/text';
        const cellUrl = 'https://example.invalid/cell';
        const forumUrl =
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=456';
        final openedThreads = <String?>[];
        final id = data.add(
          '<p>Opening paragraph</p>'
          '<p style="text-align:right">before <a href="$textUrl">LINK</a>!</p>'
          '<table width="480"><tr><td><a href="$cellUrl">CELL</a>!</td>'
          '<td>$forumUrl</td></tr></table><p>after the table</p>',
        );
        final args = NovelReaderArgs(
          novelId: id.novelId,
          episodeId: id.episodeId,
        );
        final reader = GlobalKey();
        final scope = data.scope(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NovelReaderPage(
              key: reader,
              novelId: id.novelId,
              initialEpisodeId: id.episodeId,
              nativePagination: true,
              comparisonSurfaceFactory: createLegacyNovelReaderSurface,
              nativeIdleScheduler: () async {},
            ),
          ),
          preferences: _Preferences(mode),
        ) as ProviderScope;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...scope.overrides,
              clipboardTextWriterProvider.overrideWithValue(writer),
              nativeForumLinkPageFactoryProvider.overrideWithValue((
                destination, {
                bool isActive = true,
              }) {
                openedThreads.add(destination.tid);
                return const Scaffold(body: Text('Selected thread fixture'));
              }),
            ],
            child: scope.child,
          ),
        );

        final paged = mode == NovelReaderFlowMode.pagedLtr;
        ProfileReaderObservation observe() =>
            observeProfileReader(reader.currentContext!, args);
        Future<void> until(bool Function() ready) async {
          for (var i = 0; i < 2000; i++) {
            await tester.pump(const Duration(milliseconds: 5));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1)),
            );
            if (ready()) return;
          }
          fail('Reader did not mount the requested link');
        }

        Future<void> tapLastGlyph(String label) async {
          final match = find.byWidgetPredicate(
            (widget) =>
                widget is ForumBodyParagraphSurface &&
                widget.lease.isActive &&
                widget.lease.content.projection.text.contains(label),
          );
          await until(() {
            final boundary = find
                .byType(NovelReaderDelayedLoadingBoundary)
                .evaluate()
                .singleOrNull
                ?.widget;
            return boundary is NovelReaderDelayedLoadingBoundary &&
                !boundary.isLoading &&
                match.evaluate().isNotEmpty;
          });
          final surface = tester.widget<ForumBodyParagraphSurface>(match.first);
          final layout = surface.lease.layout;
          final end =
              surface.lease.content.projection.text.indexOf(label) +
              label.length;
          final glyph = layout.selectionBoxes(end - 1, end).single;
          final point = Offset(
            glyph.left + (glyph.right - glyph.left) * .9,
            (glyph.top + glyph.bottom) * .5 -
                layout.lines[surface.startLine].top,
          );
          await tester.tapAt(tester.getTopLeft(match.first) + point);
          await tester.pump(const Duration(milliseconds: 400));
        }

        if (paged) {
          await until(() => observe().businessConfirmed && observe().complete);
        }
        await tapLastGlyph('LINK');
        expect(writer.writes, [textUrl]);
        if (paged) {
          expect(observe().page, 0);
          final surface = tester.widget<NovelReaderNativePagedSurface>(
            find.byType(NovelReaderNativePagedSurface),
          );
          expect(surface.navigationController!.turnNext(), isTrue);
          await until(() => observe().page == 1 && observe().businessConfirmed);
        }
        await tapLastGlyph('CELL');
        expect(writer.writes, [textUrl, cellUrl]);
        if (paged) expect(observe().page, 1);
        await tester.pumpAndSettle();
        final region = tester.state<SelectableRegionState>(
          find.byType(SelectableRegion),
        );
        region.selectAll(SelectionChangedCause.toolbar);
        await tester.pumpAndSettle();
        final toolbar = tester.widget<AdaptiveTextSelectionToolbar>(
          find.byType(AdaptiveTextSelectionToolbar),
        );
        final open = toolbar.buttonItems!
            .singleWhere(
              (item) =>
                  item.label ==
                  AppLocalizations.of(region.context).selectionOpenForumLink,
            )
            .onPressed!;
        open();
        open();
        await tester.pumpAndSettle();
        expect(openedThreads, ['456']);
        expect(find.text('Selected thread fixture'), findsOneWidget);
        expect(writer.writes, [textUrl, cellUrl]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

final class _Writer implements ClipboardTextWriter {
  final writes = <String>[];

  @override
  Future<void> writeText(String text) async => writes.add(text);
}

final class _Preferences implements NovelReaderPreferencesRepository {
  _Preferences(NovelReaderFlowMode mode)
    : _value = profileReaderPreferences.copyWith(flowMode: mode);

  NovelReaderPreferences _value;

  @override
  Future<NovelReaderPreferences> load() async => _value;

  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    _value = preferences;
  }
}
