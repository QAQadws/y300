import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_paged_navigation_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_chapter_turn.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_host_status.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/novel_text_resolver.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_owner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_layout_host.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_surface.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/native_reader_activity_signal.dart';

const _episode = NovelEpisodeItem(
  episodeId: 'episode',
  novelId: 'novel',
  sourceTid: '1',
  episodeTitle: 'Chapter',
  orderIndex: 0,
);

// FakeAsync cannot advance vsync while Flutter retries low-priority Timer.run
// tasks at the same timestamp. Keep the Host's existing idle test port explicit.
Future<void> _idle() async {}

class _Preparation implements NovelReaderNativePreparationService {
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<NovelReaderNativeChapterPreparation> prepare({
    required String episodeId,
    required String sourceId,
    required String rawHtml,
    required NovelReaderDocument semanticDocument,
    required NovelReaderPaginationCancellationToken cancellation,
    TextConverter converter = const IdentityTextConverter(),
  }) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('private preparation error');
    return const DefaultNovelReaderNativePreparationService().prepare(
      episodeId: episodeId,
      sourceId: sourceId,
      rawHtml: rawHtml,
      semanticDocument: semanticDocument,
      cancellation: cancellation,
      converter: converter,
    );
  }
}

class _Reader {
  _Reader({String? html}) {
    rawHtml =
        html ?? '<p>${List.filled(100, 'abcdefghijklmnopqrst').join()}</p>';
    document =
        const DiscuzNovelReaderDocumentParser(captureSourceProvenance: true)
            .parse(
              episodeId: _episode.episodeId,
              rawHtml: rawHtml,
              fallbackParagraphs: const [],
            );
    final origin = document.sourceProvenance?.origins.firstOrNull;
    snapshot = NovelReaderProgressSnapshot(
      novelId: _episode.novelId,
      episodeId: _episode.episodeId,
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 0,
      anchorNodeId: origin?.nodeId,
      anchorTextOffset: 0,
      anchorFormatVersion: 37,
      anchorTextIdentity: origin == null
          ? null
          : NovelReaderAnchorFormat.textIdentity(origin.text),
      progressPercent: 0,
      isProgressPercentValid: true,
    );
    addTearDown(() {
      navigation.dispose();
      owner.dispose();
      fonts.dispose();
    });
  }
  late final String rawHtml;
  late final NovelReaderDocument document;
  late final NovelReaderProgressSnapshot snapshot;
  final fonts = ChangeNotifier();
  late final owner = NovelReaderNativeOwner(fontChanges: fonts);
  final authority = Object();
  final navigation = NovelReaderPagedNavigationController();
  final service = _Preparation();
  final positions = <NovelReaderPaginationPosition>[];
  final statuses = <NovelReaderNativeHostStatus>[];
  final edges = <NovelReaderChapterEdge>[];
  final endConfirmations = <bool>[];
  int ready = 0;
  int terminal = 0;
  int scrollChoices = 0;
  NovelReaderPreferences get preferences =>
      NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
        fontSize: 10,
        lineHeight: 1,
        pagePadding: 8,
        paragraphSpacing: 0,
        contentMaxWidth: 240,
      );
}

Future<void> _show(
  WidgetTester tester,
  _Reader reader, {
  double width = 400,
  double height = 400,
  ReaderChromeInsets insets = const ReaderChromeInsets.zero(),
  NovelReaderPreferences? preferences,
  bool active = true,
  TextScaler scaler = TextScaler.noScaling,
  Object? authority,
  Locale locale = const Locale('zh'),
  NovelReaderPagedNavigationController? navigation,
  ValueListenable<bool>? activitySignal,
}) => tester.pumpWidget(
  LocalizedTestApp(
    locale: locale,
    theme: ThemeData.light().copyWith(
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          fontFamily: 'Ahem',
          letterSpacing: 0,
          wordSpacing: 0,
        ),
      ),
    ),
    home: MediaQuery(
      data: MediaQueryData(textScaler: scaler),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: NovelReaderNativePagedSurface(
            owner: reader.owner,
            episode: _episode,
            rawHtml: reader.rawHtml,
            semanticDocument: reader.document,
            preferences: preferences ?? reader.preferences,
            resolvedFont: ResolvedFont.system,
            progressSnapshot: reader.snapshot,
            readingAuthorityIdentity: authority ?? reader.authority,
            preparationService: reader.service,
            chromeInsets: insets,
            active: active,
            activity: activitySignal,
            navigationController: navigation ?? reader.navigation,
            previousChapterTitle: 'previous',
            nextChapterTitle: 'next',
            onTurnToAdjacentChapter: (edge) {
              reader.edges.add(edge);
              if (edge == NovelReaderChapterEdge.end) {
                reader.endConfirmations.add(
                  reader.navigation.confirmChapterEndNavigation(),
                );
              }
              return true;
            },
            onPositionChanged: reader.positions.add,
            onStatusChanged: reader.statuses.add,
            onContentReady: () => reader.ready++,
            onContentTerminal: () => reader.terminal++,
            onChooseScrollMode: () => reader.scrollChoices++,
            performance: const NovelReaderPaginationPerformancePolicy(
              enforceBudgets: false,
            ),
            idleScheduler: _idle,
          ),
        ),
      ),
    ),
  ),
);

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(NovelReaderNativePagedSurface)),
);

Future<void> _unmount(WidgetTester tester, _Reader reader) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(reader.owner.activeCacheHandles, 0);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('a native table owns its drag and keeps its offsets on return', (
    tester,
  ) async {
    final reader = _Reader(
      html:
          '<p>before</p><table width="480" cellpadding="3">'
          '<tr height="420"><td rowspan="2">first</td><td>right</td></tr>'
          '<tr><td>tail</td></tr></table><p>after</p>',
    );
    await _show(tester, reader);
    await tester.pumpAndSettle();
    final controller = reader.statuses.last.controller!;
    expect(controller.snapshot, hasLength(3));
    expect(reader.positions.last.pageIndex, 0);
    expect(reader.navigation.turnNext(), isTrue);
    await tester.pumpAndSettle();
    expect(reader.positions.last.pageIndex, 1);
    final startAnchor = reader.positions.last.anchor;
    expect(startAnchor.hasCanonicalTextOffset, isTrue);
    expect(reader.positions.last.isWholeBodyVisible, isFalse);
    final table = find.byType(ForumBodyTableBookViewport);
    final next = find.byKey(const Key('novel-reader-table-next'));
    expect(table, findsOneWidget);
    expect(find.byTooltip(_l10n(tester).novelTableNextPage), findsOneWidget);
    expect(
      tester.getRect(table).bottom,
      lessThanOrEqualTo(tester.getRect(next).top),
    );
    final viewport = tester.widget<ForumBodyTableBookViewport>(table);
    final h = viewport.horizontalController, v = viewport.verticalController;
    final maxX = h.position.maxScrollExtent, maxY = v.position.maxScrollExtent;
    expect(maxX, greaterThan(0));
    expect(maxY, greaterThan(0));
    final oldCount = reader.positions.length;
    h.jumpTo(maxX);
    v.jumpTo(maxY);
    await tester.pumpAndSettle();
    await tester.drag(table, const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(reader.positions, hasLength(oldCount));
    expect(reader.positions.last.pageIndex, 1);
    expect(reader.edges, isEmpty);

    v.jumpTo(maxY * .4);
    await tester.pumpAndSettle();
    expect(reader.positions, hasLength(oldCount));
    await tester.drag(table, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(v.offset, maxY);
    expect(reader.positions, hasLength(oldCount + 1));
    final tail = reader.positions.last;
    expect(tail.pageIndex, 1);
    expect(tail.hasUserNavigated, isTrue);
    expect(tail.isReadOnlyCompatibilityRestore, isFalse);
    expect(tail.isBodyEndVisible, isFalse);
    expect(tail.anchor.hasCanonicalTextOffset, isTrue);
    expect((
      tail.anchor.nodeId,
      tail.anchor.textOffset,
    ), isNot((startAnchor.nodeId, startAnchor.textOffset)));

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(reader.positions.last.pageIndex, 2);
    expect(reader.navigation.turnPrevious(), isTrue);
    await tester.pumpAndSettle();
    expect(reader.positions.last.pageIndex, 1);
    final returned = tester.widget<ForumBodyTableBookViewport>(table);
    expect(returned.horizontalController.offset, maxX);
    expect(returned.verticalController.offset, maxY);
    final previous = find.byKey(const Key('novel-reader-table-previous'));
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(reader.positions.last.pageIndex, 0);
    await _unmount(tester, reader);
  });

  testWidgets(
    'table reflow keeps the old layout painted until new cells mount',
    (tester) async {
      final reader = _Reader(
        html: '<table><tr><td><ruby>A<rt>a</rt></ruby> actual body</td></tr></table>',
      );
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final table = find.byType(ForumBodyTableBookViewport);
      final old = tester.widget<ForumBodyTableBookViewport>(table).layout;
      final original = reader.statuses.last.controller!;
      final initialPositions = reader.positions.length;
      await _show(
        tester,
        reader,
        preferences: reader.preferences.copyWith(fontSize: 14),
      );
      var sawStaging = false;
      for (
        var i = 0;
        i < 100 && reader.positions.length == initialPositions;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
        final allTables = find.byType(
          ForumBodyTableBookViewport,
          skipOffstage: false,
        );
        if (allTables.evaluate().length == 2) {
          sawStaging = true;
          expect(
            tester.widget<ForumBodyTableBookViewport>(table).layout,
            same(old),
          );
          expect(old.isClosed, isFalse);
        }
      }
      await tester.pumpAndSettle();
      expect(sawStaging, isTrue);
      expect(reader.statuses.last.controller, isNot(same(original)));
      expect(reader.positions.length, greaterThan(initialPositions));
      expect(reader.positions.last.isReadOnlyCompatibilityRestore, isTrue);
      expect(old.isClosed, isTrue);
      expect(reader.owner.activeCacheHandles, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'shell activity suspends before a frame and rejects stale semantics through a frameless pause/resume',
    (tester) async {
      final reader = _Reader();
      final signal = NativeReaderActivitySignal(true);
      addTearDown(signal.dispose);
      await _show(tester, reader, activitySignal: signal);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final semantics = tester.widget<Semantics>(
        find.byKey(const Key('novel-reader-native-paged-semantics')),
      );
      final position = reader.positions.last;
      expect(reader.navigation.turnNext(), isTrue);
      signal.value = false;
      expect(controller.isSuspended, isTrue);
      semantics.properties.onIncrease!();
      expect(reader.navigation.turnNext(), isFalse);
      signal.value = true;
      expect(controller.isSuspended, isTrue);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(reader.positions.last.pageIndex, position.pageIndex);
      expect(reader.positions.every((p) => !p.hasUserNavigated), isTrue);
      await _unmount(tester, reader);
      expect(signal.isObserved, isFalse);
    },
  );

  testWidgets(
    'activity loss and return retire a ready chapter pull before its release frame',
    (tester) async {
      final reader = _Reader(html: '<p>abcd</p>');
      final signal = NativeReaderActivitySignal(true);
      addTearDown(signal.dispose);
      await _show(tester, reader, activitySignal: signal);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('novel-reader-chapter-turn-hint-text')),
        findsOneWidget,
      );
      signal.value = false;
      signal.value = true;
      await gesture.up();
      await tester.pumpAndSettle();
      expect(reader.edges, isEmpty);
      expect(reader.positions.every((p) => !p.hasUserNavigated), isTrue);
      expect(
        find.byKey(const Key('novel-reader-chapter-turn-hint-text')),
        findsNothing,
      );
      await tester.drag(find.byType(PageView), const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(reader.edges, [NovelReaderChapterEdge.end]);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'stale recovery callbacks cannot retry a source or change mode while activity is off',
    (tester) async {
      final reader = _Reader(
        html:
            '<p>${List.filled(100, 'abcdefghijklmnopqrst').join()}</p><div style="position:absolute">unsupported</div>',
      );
      final signal = NativeReaderActivitySignal(true);
      addTearDown(signal.dispose);
      await _show(
        tester,
        reader,
        width: 200,
        height: 180,
        activitySignal: signal,
      );
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final error = controller.error;
      expect(error, isNotNull);
      final retry = tester
          .widget<IconButton>(
            find.byKey(const Key('novel-reader-pagination-retry')),
          )
          .onPressed!;
      final scroll = tester
          .widget<IconButton>(
            find.byKey(const Key('novel-reader-pagination-fallback')),
          )
          .onPressed!;
      signal.value = false;
      retry();
      scroll();
      expect(reader.scrollChoices, 0);
      signal.value = true;
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(controller.error, same(error));
      expect(reader.service.calls, 1);
      await tester.tap(
        find.byKey(const Key('novel-reader-pagination-fallback')),
      );
      expect(reader.scrollChoices, 1);
      await _unmount(tester, reader);
    },
  );

  for (final replacement in ['owner', 'dispose']) {
    testWidgets(
      'stale semantics after $replacement cannot follow a shared port into another reader',
      (tester) async {
        final old = _Reader();
        await _show(tester, old);
        await tester.pumpAndSettle();
        final semantics = tester.widget<Semantics>(
          find.byKey(const Key('novel-reader-native-paged-semantics')),
        );
        final staleIncrease = semantics.properties.onIncrease!;
        if (replacement == 'dispose') await _unmount(tester, old);
        final next = _Reader();
        await _show(tester, next, navigation: old.navigation);
        await tester.pumpAndSettle();
        final reports = next.positions.length;
        staleIncrease();
        await tester.pumpAndSettle();
        expect(next.positions, hasLength(reports));
        expect(old.navigation.turnNext(), isTrue);
        await tester.pumpAndSettle();
        expect(next.positions.last.pageIndex, 1);
        expect(next.positions.last.hasUserNavigated, isTrue);
        await _unmount(tester, next);
      },
    );
  }
  testWidgets(
    'an unbounded window reports one terminal geometry result without preparing content',
    (tester) async {
      final reader = _Reader();
      await tester.pumpWidget(
        LocalizedTestApp(
          home: SingleChildScrollView(
            child: NovelReaderNativePagedSurface(
              owner: reader.owner,
              episode: _episode,
              rawHtml: reader.rawHtml,
              semanticDocument: reader.document,
              preferences: reader.preferences,
              resolvedFont: ResolvedFont.system,
              progressSnapshot: reader.snapshot,
              readingAuthorityIdentity: reader.authority,
              preparationService: reader.service,
              onContentTerminal: () => reader.terminal++,
              onStatusChanged: reader.statuses.add,
              onPositionChanged: reader.positions.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(_l10n(tester).novelPagedWindowUnavailable),
        findsOneWidget,
      );
      expect(reader.terminal, 1);
      expect(reader.statuses.single.phase, NovelReaderNativeHostPhase.failed);
      expect(reader.service.calls, 0);
      expect(reader.positions, isEmpty);
      await _unmount(tester, reader);
    },
  );

  for (final preset in [
    NovelReaderThemePreset.dark,
    NovelReaderThemePreset.sepia,
  ]) {
    testWidgets(
      'recovery uses the selected reader palette for $preset on a light app theme',
      (tester) async {
        final reader = _Reader()..service.fail = true;
        final preferences = reader.preferences.copyWith(themePreset: preset);
        await _show(tester, reader, preferences: preferences);
        await tester.pumpAndSettle();
        final context = tester.element(
          find.byType(NovelReaderNativePagedSurface),
        );
        final palette = const NovelReaderThemeResolver().resolve(
          preferences: preferences,
          theme: Theme.of(context),
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('novel-reader-pagination-paused')),
              )
              .style!
              .color,
          palette.muted,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const Key('novel-reader-pagination-retry')),
              )
              .color,
          palette.foreground,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const Key('novel-reader-pagination-fallback')),
              )
              .color,
          palette.foreground,
        );
        await _unmount(tester, reader);
      },
    );
  }
  for (final height in [50.0, 180.0]) {
    testWidgets(
      'narrow recovery fits width=100 height=$height without inventing a page',
      (tester) async {
        final reader = _Reader()..service.fail = true;
        await _show(tester, reader, width: 100, height: height);
        await tester.pumpAndSettle();
        expect(reader.positions, isEmpty);
        expect(reader.scrollChoices, 0);
        expect(
          find.byKey(const Key('novel-reader-pagination-retry')),
          findsOneWidget,
        );
        await _unmount(tester, reader);
      },
    );
  }

  testWidgets(
    'Traditional Chinese recovery uses current locale and keeps failures private',
    (tester) async {
      final reader = _Reader()..service.fail = true;
      await _show(tester, reader, locale: const Locale('zh', 'TW'));
      await tester.pumpAndSettle();
      expect(_l10n(tester).localeName, 'zh_TW');
      expect(find.text(_l10n(tester).novelPagedLayoutFailed), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('novel-reader-pagination-retry')),
            )
            .tooltip,
        _l10n(tester).commonRetry,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('novel-reader-pagination-fallback')),
            )
            .tooltip,
        _l10n(tester).novelReturnToScroll,
      );
      expect(find.textContaining('private preparation error'), findsNothing);
      await _unmount(tester, reader);
    },
  );
  testWidgets(
    'one exact body box excludes margins, safe area, persistent chrome and footer',
    (tester) async {
      final reader = _Reader();
      await _show(
        tester,
        reader,
        height: 600,
        insets: const ReaderChromeInsets(
          top: 12,
          safeAreaTop: 30,
          bottom: 14,
          safeAreaBottom: 20,
          pageIndicatorReservedHeight: 18,
        ),
      );
      await tester.pumpAndSettle();
      final body = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
      final footer = tester.getRect(
        find.byKey(const Key('novel-reader-native-footer')),
      );
      expect(body, const Rect.fromLTWH(80, 50, 240, 460));
      expect(footer.top, body.bottom);
      expect(body.overlaps(footer), isFalse);
      final snapshot = reader.statuses.last.controller!.snapshot!;
      expect(snapshot.width, body.width);
      expect(snapshot.height, body.height);
      expect(reader.positions.first.isReadOnlyCompatibilityRestore, isTrue);
      expect(
        find.byKey(const Key('novel-reader-page-indicator-text')),
        findsOneWidget,
      );
      await _unmount(tester, reader);
    },
  );

  for (final size in [
    const Size(400, 600),
    const Size(700, 350),
    const Size(210, 450),
  ]) {
    for (final full in [false, true]) {
      testWidgets(
        'independent physical edges and width agree with actual native body $size/full=$full',
        (tester) async {
          final reader = _Reader();
          const insets = ReaderChromeInsets(
            top: 12,
            safeAreaTop: 30,
            bottom: 14,
            safeAreaBottom: 20,
          );
          final preferences = reader.preferences.copyWith(
            viewport: NovelReaderViewportOverrides(
              left: 10,
              top: 20,
              right: 30,
              bottom: 40,
              contentWidth: full
                  ? const NovelReaderContentWidth.available(logicalPixels: 200)
                  : const NovelReaderContentWidth.limited(200),
            ),
          );
          await _show(
            tester,
            reader,
            width: size.width,
            height: size.height,
            insets: insets,
            preferences: preferences,
          );
          await tester.pumpAndSettle();
          final body = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
          final footer = tester.getRect(
            find.byKey(const Key('novel-reader-native-footer')),
          );
          final available = size.width - 40;
          final width = full || available < 200 ? available : 200.0;
          expect(
            body,
            Rect.fromLTWH(
              10 + (available - width) / 2,
              62,
              width,
              size.height - 184,
            ),
          );
          expect(footer.top, body.bottom);
          expect(footer.height, 48);
          final snapshot = reader.statuses.last.controller!.snapshot!;
          expect((snapshot.width, snapshot.height), (body.width, body.height));
          expect(reader.scrollChoices, 0);
          await _unmount(tester, reader);
        },
      );
    }
  }
  testWidgets(
    'viewport origin-only changes reuse the actual controller and keep physical RTL edges',
    (tester) async {
      final reader = _Reader();
      final preferences = reader.preferences.copyWith(
        viewport: const NovelReaderViewportOverrides(
          left: 10,
          top: 20,
          right: 30,
          bottom: 40,
          contentWidth: NovelReaderContentWidth.available(logicalPixels: 200),
        ),
      );
      await _show(tester, reader, preferences: preferences);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller;
      final before = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
      final reports = reader.positions.length;
      await _show(
        tester,
        reader,
        preferences: preferences.copyWith(
          flowMode: NovelReaderFlowMode.pagedRtl,
          viewport: const NovelReaderViewportOverrides(
            left: 30,
            top: 25,
            right: 10,
            bottom: 35,
            contentWidth: NovelReaderContentWidth.available(logicalPixels: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
      expect(after, before.shift(const Offset(20, 5)));
      expect(reader.statuses.last.controller, same(controller));
      expect(reader.positions.length, reports);
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );
  testWidgets(
    'invalid viewport input reports geometry once without opening a native session',
    (tester) async {
      final reader = _Reader();
      final bad = reader.preferences.copyWith(
        viewport: const NovelReaderViewportOverrides(left: -1),
      );
      await _show(tester, reader, preferences: bad);
      await tester.pumpAndSettle();
      expect(reader.terminal, 1);
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.failed);
      expect(reader.owner.activeCacheHandles, 0);
      await _show(tester, reader, preferences: bad);
      await tester.pumpAndSettle();
      expect(reader.terminal, 1);
      expect(tester.takeException(), isNull);
      await _unmount(tester, reader);
    },
  );
  testWidgets(
    'a valid request exceeding the current window fails without changing preferences or mode',
    (tester) async {
      final reader = _Reader();
      final preferences = reader.preferences.copyWith(
        viewport: const NovelReaderViewportOverrides(
          left: 96,
          top: 96,
          right: 96,
          bottom: 96,
          contentWidth: NovelReaderContentWidth.available(logicalPixels: 240),
        ),
      );
      await _show(
        tester,
        reader,
        width: 150,
        height: 180,
        preferences: preferences,
      );
      await tester.pumpAndSettle();
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.failed);
      expect(reader.statuses.last.pageCount, 0);
      expect(reader.statuses.last.hasVisiblePage, false);
      expect(reader.positions, isEmpty);
      expect(reader.scrollChoices, 0);
      expect(reader.owner.activeCacheHandles, 0);
      expect(
        tester
            .widget<NovelReaderNativePagedSurface>(
              find.byType(NovelReaderNativePagedSurface),
            )
            .preferences,
        preferences,
      );
      expect(tester.takeException(), isNull);
      await _unmount(tester, reader);
    },
  );
  testWidgets(
    'scaled footer stays outside reflowed native text and retains its canonical point',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final before = reader.statuses.last.controller;
      final body = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
      await _show(tester, reader, scaler: const TextScaler.linear(3));
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
      final footer = tester.getRect(
        find.byKey(const Key('novel-reader-native-footer')),
      );
      expect(after.height, lessThan(body.height));
      expect(after.overlaps(footer), isFalse);
      expect(reader.statuses.last.controller, isNot(same(before)));
      expect(
        reader.positions.last.anchor.textOffset,
        reader.positions.first.anchor.textOffset,
      );
      expect(
        reader.positions.every(
          (p) => p.isReadOnlyCompatibilityRestore && !p.hasUserNavigated,
        ),
        isTrue,
      );
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'indicator visibility follows actual fixed-footer geometry without reparsing or new positions',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final before = reader.statuses.last.controller;
      final box = tester.getSize(find.byType(NovelReaderNativeLayoutHost));
      final reports = reader.positions.length;
      await _show(
        tester,
        reader,
        preferences: reader.preferences.copyWith(showProgressIndicator: false),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('novel-reader-page-indicator-text')),
        findsNothing,
      );
      expect(tester.getSize(find.byType(NovelReaderNativeLayoutHost)), box);
      expect(reader.statuses.last.controller, same(before));
      expect(reader.positions, hasLength(reports));
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );

  for (final rtl in [false, true]) {
    testWidgets(
      'localized visible hint does not cover text or reflow while pulling in rtl=$rtl',
      (tester) async {
        final reader = _Reader(html: '<p>abcd</p>');
        await _show(
          tester,
          reader,
          preferences: reader.preferences.copyWith(
            flowMode: rtl
                ? NovelReaderFlowMode.pagedRtl
                : NovelReaderFlowMode.pagedLtr,
          ),
        );
        await tester.pumpAndSettle();
        final box = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
        final controller = reader.statuses.last.controller;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(PageView)),
        );
        await gesture.moveBy(Offset(rtl ? 80 : -80, 0));
        await tester.pumpAndSettle();
        final hint = find.byKey(
          const Key('novel-reader-chapter-turn-hint-text'),
        );
        expect(
          tester.widget<Text>(hint).data,
          NovelTextResolver.chapterTurnHint(
            _l10n(tester),
            const NovelReaderChapterTurnHint(
              edge: NovelReaderChapterEdge.end,
              chapterTitle: 'next',
              isReadyToCommit: true,
            ),
          ),
        );
        expect(tester.getRect(hint).overlaps(box), isFalse);
        expect(tester.getRect(find.byType(NovelReaderNativeLayoutHost)), box);
        expect(reader.statuses.last.controller, same(controller));
        expect(reader.edges, isEmpty);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(reader.edges, [NovelReaderChapterEdge.end]);
        expect(reader.endConfirmations, [true]);
        expect(reader.positions.last.hasUserNavigated, isTrue);
        expect(
          find.byKey(const Key('novel-reader-chapter-turn-hint-text')),
          findsNothing,
        );
        await _unmount(tester, reader);
      },
    );
  }

  testWidgets(
    'initial failure uses localized recovery and explicit retry keeps the same body box',
    (tester) async {
      final reader = _Reader()..service.fail = true;
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final box = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
      expect(find.text(_l10n(tester).novelPagedLayoutFailed), findsOneWidget);
      expect(find.textContaining('private preparation error'), findsNothing);
      expect(reader.positions, isEmpty);
      expect(reader.scrollChoices, 0);
      reader.service.fail = false;
      await tester.tap(find.byKey(const Key('novel-reader-pagination-retry')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(NovelReaderNativeLayoutHost)), box);
      expect(reader.service.calls, 2);
      expect(reader.ready, 1);
      expect(reader.positions.single.isReadOnlyCompatibilityRestore, isTrue);
      expect(reader.scrollChoices, 0);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'only an explicit scroll choice calls the mode callback and hidden recovery is disabled',
    (tester) async {
      final reader = _Reader()..service.fail = true;
      await _show(tester, reader);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('novel-reader-pagination-fallback')),
      );
      expect(reader.scrollChoices, 1);
      await _show(tester, reader, active: false);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('novel-reader-pagination-retry')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('novel-reader-pagination-fallback')),
            )
            .onPressed,
        isNull,
      );
      expect(reader.service.calls, 1);
      expect(reader.positions, isEmpty);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'a late source failure preserves native pages with recovery outside their geometry',
    (tester) async {
      final reader = _Reader(
        html:
            '<p>${List.filled(100, 'abcdefghijklmnopqrst').join()}</p><div style="position:absolute">unsupported</div>',
      );
      await _show(tester, reader, width: 200, height: 180);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.paused);
      final box = tester.getRect(find.byType(NovelReaderNativeLayoutHost));
      expect(find.byType(ForumBodyTextPageSurface), findsWidgets);
      expect(
        tester
            .getRect(find.byKey(const Key('novel-reader-pagination-retry')))
            .overlaps(box),
        isFalse,
      );
      expect(reader.navigation.turnNext(), isTrue);
      await tester.pumpAndSettle();
      expect(reader.positions.last.pageIndex, 1);
      expect(reader.positions.last.hasUserNavigated, isTrue);
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.paused);
      expect(reader.scrollChoices, 0);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'empty source renders localized empty state without a page or native cache handle',
    (tester) async {
      final reader = _Reader(html: '');
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(find.text(_l10n(tester).novelPagedNoContent), findsOneWidget);
      expect(
        find.byKey(const Key('novel-reader-page-indicator-text')),
        findsNothing,
      );
      expect(reader.positions, isEmpty);
      expect(reader.owner.activeCacheHandles, 0);
      expect(reader.terminal, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'hidden shell retains paint but disables navigation until same-controller resume',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller;
      final reports = reader.positions.length;
      await _show(tester, reader, active: false);
      await tester.pumpAndSettle();
      expect(find.byType(ForumBodyTextPageSurface), findsWidgets);
      expect(reader.navigation.turnNext(), isFalse);
      final semantics = tester.widget<Semantics>(
        find.byKey(const Key('novel-reader-native-paged-semantics')),
      );
      expect(semantics.properties.onIncrease, isNull);
      expect(reader.positions, hasLength(reports));
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(reader.service.calls, 1);
      expect(reader.positions.every((p) => !p.hasUserNavigated), isTrue);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'new owner suppresses the old pending shell and preparation callbacks',
    (tester) async {
      final old = _Reader()..service.gate = Completer<void>();
      await _show(tester, old);
      await tester.pumpAndSettle();
      final next = _Reader(html: '<p>abcd</p>');
      await _show(tester, next);
      await tester.pumpAndSettle();
      old.service.gate!.complete();
      await tester.pumpAndSettle();
      expect(old.positions, isEmpty);
      expect(old.ready, 0);
      expect(next.positions, hasLength(1));
      expect(old.owner.activeCacheHandles, 0);
      await _unmount(tester, next);
    },
  );

  testWidgets(
    'semantic page action uses the same native navigation and confirms only actual arrival',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final semantics = tester.widget<Semantics>(
        find.byKey(const Key('novel-reader-native-paged-semantics')),
      );
      expect(semantics.properties.onIncrease, isNotNull);
      final reports = reader.positions.length;
      semantics.properties.onIncrease!();
      expect(reader.positions, hasLength(reports));
      await tester.pumpAndSettle();
      expect(reader.positions.last.pageIndex, 1);
      expect(reader.positions.last.hasUserNavigated, isTrue);
      await _unmount(tester, reader);
    },
  );
}
