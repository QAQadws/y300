import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_host_status.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_anchor_navigation_request.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_chapter_turn.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_paged_navigation_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_text_selection.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_exception.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_owner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_layout_host.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

import '../test_support/native_reader_activity_signal.dart';

Future<void> _idle() async {}
const _canvasKey = Key('native-host-canvas');

class _Preparation implements NovelReaderNativePreparationService {
  int calls = 0;
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
    if (gate != null) await gate!.future;
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
  _Reader({
    String? html,
    this.episodeId = 'episode',
    this.maxParagraphEntries = 64,
    this.maxParagraphEstimatedBytes = 16 * 1024 * 1024,
  }) {
    rawHtml =
        html ?? '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p>';
    semantic =
        const DiscuzNovelReaderDocumentParser(captureSourceProvenance: true)
            .parse(
              episodeId: episodeId,
              rawHtml: rawHtml,
              fallbackParagraphs: const [],
            );
    final origin = semantic.sourceProvenance?.origins.firstOrNull;
    snapshot = NovelReaderProgressSnapshot(
      novelId: 'novel',
      episodeId: episodeId,
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 0,
      anchorNodeId: origin?.nodeId,
      anchorTextOffset: 73,
      anchorFormatVersion: 1,
      anchorTextIdentity: origin == null
          ? null
          : NovelReaderAnchorFormat.textIdentity(origin.text),
      progressPercent: .5,
      isProgressPercentValid: true,
    );
    addTearDown(() {
      owner.dispose();
      fonts.dispose();
    });
  }
  final String episodeId;
  final int maxParagraphEntries;
  final int maxParagraphEstimatedBytes;
  late final String rawHtml;
  late final NovelReaderDocument semantic;
  late NovelReaderProgressSnapshot snapshot;
  final fonts = ChangeNotifier();
  late final owner = NovelReaderNativeOwner(
    fontChanges: fonts,
    maxParagraphEntries: maxParagraphEntries,
    maxParagraphEstimatedBytes: maxParagraphEstimatedBytes,
  );
  final service = _Preparation();
  final authority = Object();
  final positions = <NovelReaderPaginationPosition>[];
  final statuses = <NovelReaderNativeHostStatus>[];
  final activity = <bool>[];
  final chapterHints = <NovelReaderChapterTurnHint?>[];
  final seekResults =
      <(NovelReaderPageSeekRequest, NovelReaderPageSeekOutcome)>[];
  final anchorResults =
      <(NovelReaderAnchorNavigationRequest, NovelReaderNavigationOutcome)>[];
  int ready = 0;
  final appliedEntries = <NovelReaderChapterEntryRequest>[];
  final retiredEntries = <NovelReaderChapterEntryRequest>[];
  VoidCallback? onEntryApplied;
  ValueChanged<NovelReaderPaginationPosition>? onPosition;
  int terminal = 0;
  NovelReaderPreferences get preferences => NovelReaderPreferences.defaults()
      .copyWith(fontSize: 10, lineHeight: 1, paragraphSpacing: 0);
}

Future<void> _show(
  WidgetTester tester,
  _Reader reader, {
  double width = 100,
  double height = 40,
  NovelReaderPreferences? preferences,
  NovelReaderProgressSnapshot? snapshot,
  Object? authority,
  TextScaler scaler = TextScaler.noScaling,
  int retry = 0,
  ThemeData? theme,
  NovelReaderNativeWorkScheduler scheduler =
      const NovelReaderNativeWorkScheduler(),
  ForumBodyTextPageSessionLimits? limits,
  String? rawHtml,
  NovelReaderDocument? semantic,
  bool active = true,
  ValueListenable<bool>? activitySignal,
  NovelReaderPagedNavigationController? navigation,
  NovelReaderChapterTurnHandler? onChapter,
  String? previousTitle,
  String? nextTitle,
  bool chapterInFlight = false,
  NovelReaderChapterTurnPolicy chapterPolicy =
      const NovelReaderChapterTurnPolicy(),
  NovelReaderPageSeekRequest? seek,
  NovelReaderAnchorNavigationRequest? anchorNavigation,
  ValueChanged<NovelReaderNativeTextSelection>? onTextSelection,
  bool startsAtBeginning = false,
  NovelReaderChapterEntryRequest? entry,
  NovelReaderPaginationPerformancePolicy performance =
      const NovelReaderPaginationPerformancePolicy(enforceBudgets: false),
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: scaler),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(
          data: (theme ?? ThemeData.light()).copyWith(
            textTheme: const TextTheme(
              bodyMedium: TextStyle(
                fontFamily: 'Ahem',
                letterSpacing: 0,
                wordSpacing: 0,
              ),
            ),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: height,
              child: RepaintBoundary(
                key: _canvasKey,
                child: NovelReaderNativeLayoutHost(
                  key: const Key('host'),
                  owner: reader.owner,
                  sourceId: reader.episodeId,
                  rawHtml: rawHtml ?? reader.rawHtml,
                  semanticDocument: semantic ?? reader.semantic,
                  preferences: preferences ?? reader.preferences,
                  resolvedFont: ResolvedFont.system,
                  progressSnapshot: snapshot ?? reader.snapshot,
                  readingAuthorityIdentity: authority ?? reader.authority,
                  active: active,
                  activity: activitySignal,
                  navigationController: navigation,
                  onTurnToAdjacentChapter: onChapter,
                  previousChapterTitle: previousTitle,
                  nextChapterTitle: nextTitle,
                  chapterTurnIsInFlight: chapterInFlight,
                  chapterTurnPolicy: chapterPolicy,
                  onChapterTurnHintChanged: reader.chapterHints.add,
                  pageSeekRequest: seek,
                  navigationRequest: anchorNavigation,
                  onTextSelection: onTextSelection,
                  startsAtBeginning: startsAtBeginning,
                  chapterEntryRequest: entry,
                  onChapterEntryApplied: (request) {
                    reader.appliedEntries.add(request);
                    reader.onEntryApplied?.call();
                  },
                  onChapterEntryRetired: reader.retiredEntries.add,
                  onNavigationFinished: (request, outcome) =>
                      reader.anchorResults.add((request, outcome)),
                  onPageSeekFinished: (request, outcome) =>
                      reader.seekResults.add((request, outcome)),
                  preparationService: reader.service,
                  onPositionChanged: (position) {
                    reader.positions.add(position);
                    reader.onPosition?.call(position);
                  },
                  onStatusChanged: reader.statuses.add,
                  onContentReady: () => reader.ready++,
                  onContentTerminal: () => reader.terminal++,
                  onScrollActivityChanged: reader.activity.add,
                  retryRevision: retry,
                  scheduler: scheduler,
                  sessionLimits:
                      limits ??
                      const ForumBodyTextPageSessionLimits(
                        maxPages: 10000,
                        maxFragments: 100000,
                        maxParagraphs: 16384,
                        maxTextCodeUnits: 1024 * 1024,
                        maxRuns: 100000,
                        maxIssuedLeases: 512,
                      ),
                  idleScheduler: _idle,
                  performance: performance,
                  placeholderBuilder: (context, status) =>
                      SizedBox(key: ValueKey(status.phase)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _unmount(WidgetTester tester, _Reader reader) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(reader.owner.activeCacheHandles, 0);
  expect(tester.takeException(), isNull);
}

Future<List<int>> _canvasPixel(WidgetTester tester, {int? x, int? y}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_canvasKey),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  try {
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    // A one-row fixture leaves this corner outside all text glyphs.
    final offset =
        ((y ?? image.height - 1) * image.width + (x ?? image.width - 1)) * 4;
    return bytes.buffer.asUint8List(bytes.offsetInBytes + offset, 4).toList();
  } finally {
    image.dispose();
  }
}

void main() {
  testWidgets('fold reflow preserves its source and retires old controls', (
    tester,
  ) async {
    final reader = _Reader(
      html:
          '<p>before</p>'
          '<div class="showcollapse_box">'
          '<div class="showcollapse_title">same title</div>'
          '<div class="showcollapse_content" style="display:none">'
          '<p>outer body</p><div class="showcollapse_box showcollapse_active">'
          '<div class="showcollapse_title">same title</div>'
          '<div class="showcollapse_content" style="display:none">'
          '<p>inner body</p><div class="showcollapse_gather">control</div>'
          '</div></div></div></div><p>after</p>',
    );
    final viewport = find.byType(NovelReaderNativePagedViewport);
    final toggles = find.byWidgetPredicate(
      (widget) =>
          widget is InkWell &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'forum-native-collapse-toggle-',
          ),
    );
    await _show(
      tester,
      reader,
      width: 220,
      height: 180,
      startsAtBeginning: true,
    );
    await tester.pumpAndSettle();
    final closed = tester
        .widget<NovelReaderNativePagedViewport>(viewport)
        .controller;
    final before = reader.positions.last.anchor;
    Object anchorKey(NovelReaderTextAnchor anchor) => (
      anchor.episodeId,
      anchor.nodeId,
      anchor.textOffset,
      anchor.formatVersion,
      anchor.textIdentity,
    );
    expect(toggles, findsOneWidget);
    final oldTap = tester.widget<InkWell>(toggles).onTap!;
    await tester.tap(toggles);
    await tester.pumpAndSettle();
    final opened = tester
        .widget<NovelReaderNativePagedViewport>(viewport)
        .controller;
    expect(opened, isNot(same(closed)));
    expect(opened.paginationKey, isNot(closed.paginationKey));
    expect(toggles, findsNWidgets(2));
    expect(anchorKey(reader.positions.last.anchor), anchorKey(before));
    expect(reader.positions.last.isReadOnlyCompatibilityRestore, isTrue);
    oldTap();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NovelReaderNativePagedViewport>(viewport).controller,
      same(opened),
    );

    await _show(
      tester,
      reader,
      width: 230,
      height: 180,
      startsAtBeginning: true,
    );
    await tester.pumpAndSettle();
    expect(toggles, findsNWidgets(2));
    final resized = tester
        .widget<NovelReaderNativePagedViewport>(viewport)
        .controller;
    final resizedView = resized.visibleView!;
    final resizedFragments =
        resizedView.snapshot[resizedView.pageIndex].fragments;
    final innerTitle = resizedFragments.lastIndexWhere(
      (fragment) => fragment.collapseHeader != null,
    );
    final innerBody = resizedView.coverage.points
        .firstWhere((point) => point.fragmentIndex == innerTitle + 1)
        .anchor;
    resized.requestAnchor(innerBody);
    await tester.pumpAndSettle();
    expect(anchorKey(reader.positions.last.anchor), anchorKey(innerBody));
    await tester.tap(toggles.last);
    await tester.pumpAndSettle();
    expect(toggles, findsNWidgets(2));
    final innerClosed = tester
        .widget<NovelReaderNativePagedViewport>(viewport)
        .controller;
    final view = innerClosed.visibleView!;
    expect(
      view.snapshot[view.pageIndex].fragments
          .map((fragment) => fragment.collapseHeader?.expanded)
          .whereType<bool>(),
      [true, false],
    );
    expect(reader.positions.last.isReadOnlyCompatibilityRestore, isTrue);
    final location = view.coverage.locate(reader.positions.last.anchor)!;
    final title =
        view.snapshot[view.pageIndex].fragments[location.fragmentIndex];
    expect(title.collapseHeader?.expanded, isFalse);
    expect(reader.service.calls, 1);
    await _unmount(tester, reader);
  });

  testWidgets(
    'real Host seals by actual owner bytes and turns without waiting on its visible page',
    (tester) async {
      final reader = _Reader(
        html: List.filled(
          6,
          // Keep natural font boxes roomy: this fixture isolates page byte
          // admission, rather than the separate tight-row font-frame budget.
          '<p style="font-size:2px;line-height:2">${'A' * 1000}</p>',
        ).join(),
        maxParagraphEstimatedBytes: 500000,
      );
      await _show(tester, reader, startsAtBeginning: true, height: 400);
      await tester.pumpAndSettle();
      expect(
        reader.statuses.last.phase,
        NovelReaderNativeHostPhase.reading,
        reason: '${reader.statuses.last.error}',
      );
      final controller = reader.statuses.last.controller!;
      expect(controller.snapshot!.length, 3);
      expect(
        controller.snapshot!.every(
          (page) => page.fragments.length == 2 && page.usedHeight < 400,
        ),
        isTrue,
      );
      final cache = reader.owner.acquireCache();
      try {
        expect(controller.requestPage(1), isTrue);
        await tester.pumpAndSettle();
        expect(controller.visiblePageIndex, 1);
        expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.reading);
        expect(cache.cache.estimatedRetainedBytes, lessThanOrEqualTo(500000));
        expect(controller.requestPage(2), isTrue);
        await tester.pumpAndSettle();
        expect(controller.visiblePageIndex, 2);
        expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.reading);
      } finally {
        cache.release();
      }
      await _unmount(tester, reader);
    },
  );
  testWidgets(
    'reflow can replace a mounted page when its old cache is fully pinned',
    (tester) async {
      final reader = _Reader(
        html: '<p>abcdefghij</p><p>klmnopqrst</p>',
        maxParagraphEntries: 2,
      );
      await _show(tester, reader, startsAtBeginning: true);
      await tester.pumpAndSettle();
      final oldController = reader.statuses.last.controller!;
      final old = reader.owner.acquireCache();
      ForumBodyParagraphLease? pinnedFont;
      if (old.cache.activeLeases < 2) {
        // Neighbor prefetch is optional. Fill the remaining slot explicitly so
        // parallel tester timing cannot weaken this handoff pressure regression.
        final content = tester
            .widget<ForumBodyParagraphSurface>(
              find.byType(ForumBodyParagraphSurface).first,
            )
            .lease
            .content;
        pinnedFont = old.cache.acquire(
          content: ForumBodyParagraphContent.anonymousInline(
            identity: content.identity,
            fontRevision: content.fontRevision,
            styleRevision: content.styleRevision,
            style: content.style,
          ),
          width: 100,
        );
      }
      expect(old.cache.activeLeases, 2);
      final oldBuilds = old.cache.layoutBuildCount;
      await _show(
        tester,
        reader,
        startsAtBeginning: true,
        preferences: reader.preferences.copyWith(fontSize: 12),
      );
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (reader.statuses.last.phase == NovelReaderNativeHostPhase.reading &&
            !identical(reader.statuses.last.controller, oldController) &&
            reader.statuses.last.controller!.visiblePageIndex == 0) {
          break;
        }
      }
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.reading);
      expect(reader.statuses.last.controller, isNot(same(oldController)));
      expect(reader.statuses.last.controller!.visiblePageIndex, 0);
      expect(find.byType(ForumBodyParagraphSurface), findsWidgets);
      expect(
        tester
            .widgetList<ForumBodyParagraphSurface>(
              find.byType(ForumBodyParagraphSurface),
            )
            .every((surface) => surface.lease.isActive),
        isTrue,
      );
      expect(old.cache.layoutBuildCount, oldBuilds);
      pinnedFont?.release();
      old.release();
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'color preference canvas reuses moving navigation but a concurrent font change relayouts',
    (tester) async {
      final reader = _Reader();
      final navigation = NovelReaderPagedNavigationController();
      addTearDown(navigation.dispose);
      final theme = ThemeData.light().copyWith(
        colorScheme: ThemeData.light().colorScheme.copyWith(
          primary: const Color(0xff000000),
        ),
      );
      final original = reader.preferences.copyWith(
        colors: const NovelReaderColorOverrides(
          foreground: 0,
          background: 0xffffff,
        ),
      );
      final changed = original.copyWith(
        colors: original.colors.withBackground(0xfff0cc),
      );
      await _show(
        tester,
        reader,
        theme: theme,
        preferences: original,
        height: 45,
        navigation: navigation,
        startsAtBeginning: true,
      );
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final handle = reader.owner.acquireCache();
      final builds = handle.cache.layoutBuildCount;
      final pictures = handle.cache.pictureBuildCount;
      final reports = reader.positions.length;
      expect(navigation.turnNext(), true);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 40));
      final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
      expect(pages.page, inExclusiveRange(0.0, 1.0));
      final revision = controller.navigationRevision;
      await _show(
        tester,
        reader,
        theme: theme,
        preferences: changed,
        height: 45,
        navigation: navigation,
        startsAtBeginning: true,
      );
      expect(controller.navigationRevision, revision);
      expect(reader.statuses.last.controller, same(controller));
      await tester.pumpAndSettle();
      expect(controller.visiblePageIndex, 1);
      expect(reader.positions, hasLength(reports + 1));
      expect(handle.cache.layoutBuildCount, builds);
      expect(handle.cache.pictureBuildCount, pictures);
      expect(await _canvasPixel(tester), [255, 240, 204, 255]);
      await _show(
        tester,
        reader,
        theme: theme,
        preferences: original.copyWith(fontSize: 22),
        height: 45,
        navigation: navigation,
        startsAtBeginning: true,
      );
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, isNot(same(controller)));
      final replacement = reader.owner.acquireCache();
      expect(replacement.cache, isNot(same(handle.cache)));
      expect(replacement.cache.layoutBuildCount, greaterThan(0));
      expect(handle.cache.layoutBuildCount, builds);
      replacement.release();
      handle.release();
      await _unmount(tester, reader);
    },
  );
  testWidgets(
    'canvas context change preserves a moving tap through actual arrival',
    (tester) async {
      final reader = _Reader();
      final navigation = NovelReaderPagedNavigationController();
      addTearDown(navigation.dispose);
      final theme = ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xff00ff00),
      );
      await _show(
        tester,
        reader,
        theme: theme,
        navigation: navigation,
        startsAtBeginning: true,
      );
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final reports = reader.positions.length;
      expect(navigation.turnNext(), true);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 40));
      final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
      final before = pages.page!;
      expect(before, inExclusiveRange(0.0, 1.0));
      final revision = controller.navigationRevision;
      await _show(
        tester,
        reader,
        theme: theme.copyWith(scaffoldBackgroundColor: const Color(0xff0000ff)),
        navigation: navigation,
        startsAtBeginning: true,
      );
      expect(reader.statuses.last.controller, same(controller));
      expect(controller.navigationRevision, revision);
      expect(controller.hasPendingNavigation, true);
      await tester.pump(const Duration(milliseconds: 16));
      expect(pages.page!, greaterThan(before));
      expect(pages.page!, lessThan(1));
      await tester.pumpAndSettle();
      expect(controller.visiblePageIndex, 1);
      expect(reader.positions, hasLength(reports + 1));
      expect(reader.positions.last.pageIndex, 1);
      await _unmount(tester, reader);
    },
  );
  testWidgets(
    'canvas context change preserves an outstanding semantic navigation request',
    (tester) async {
      final reader = _Reader();
      var held = false;
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await gate.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      final theme = ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xff00ff00),
      );
      await _show(tester, reader, theme: theme, scheduler: scheduler);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final actual = reader.positions.last;
      final reports = reader.positions.length;
      held = true;
      final request = NovelReaderAnchorNavigationRequest(
        requestId: 1,
        anchor: actual.anchor.copyWith(textOffset: 325),
      );
      await _show(
        tester,
        reader,
        theme: theme,
        scheduler: scheduler,
        anchorNavigation: request,
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.hasPendingNavigation, true);
      final revision = controller.navigationRevision;
      await _show(
        tester,
        reader,
        theme: theme.copyWith(scaffoldBackgroundColor: const Color(0xff0000ff)),
        scheduler: scheduler,
        anchorNavigation: request,
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(reader.statuses.last.controller, same(controller));
      expect(controller.navigationRevision, revision);
      expect(controller.hasPendingNavigation, true);
      expect(reader.positions, hasLength(reports));
      expect(reader.positions.last, same(actual));
      expect(reader.anchorResults, isEmpty);
      held = false;
      gate.complete();
      await tester.pumpAndSettle();
      expect(controller.visiblePageIndex, 8);
      expect(reader.positions.last.pageIndex, 8);
      expect(reader.anchorResults, [
        (request, NovelReaderNavigationOutcome.arrived),
      ]);
      await _unmount(tester, reader);
    },
  );
  for (final suspended in [false, true]) {
    // Canvas paint never changes the normal activity/resume qualification.
    testWidgets(
      'accepted canvas paint reuses pages and native resources (suspended=$suspended)',
      (tester) async {
        final reader = _Reader(
          html: '<p><span style="background-color:#ffff00">a b</span></p>',
        );
        final theme = ThemeData.light().copyWith(
          scaffoldBackgroundColor: const Color(0xff00ff00),
        );
        final nextTheme = theme.copyWith(
          scaffoldBackgroundColor: const Color(0xff0000ff),
        );
        await _show(tester, reader, theme: theme, startsAtBeginning: true);
        await tester.pumpAndSettle();
        final controller = reader.statuses.last.controller!;
        final page = controller.visiblePageIndex!;
        final view = controller.viewForPage(page);
        final reports = reader.positions.length;
        final surface = tester.renderObject(
          find.byType(ForumBodyParagraphSurface).first,
        );
        final handle = reader.owner.acquireCache();
        final builds = handle.cache.layoutBuildCount;
        final pictures = handle.cache.pictureBuildCount;
        final expectedPosition = reader.positions.last.anchor;
        final userNavigation = reader.positions.last.hasUserNavigated;
        final compatibilityRestore =
            reader.positions.last.isReadOnlyCompatibilityRestore;
        expect(await _canvasPixel(tester), [0, 255, 0, 255]);
        expect(await _canvasPixel(tester, x: 15, y: 5), [255, 255, 0, 255]);
        await _show(
          tester,
          reader,
          theme: nextTheme,
          active: !suspended,
          startsAtBeginning: true,
        );
        await tester.pumpAndSettle();
        if (suspended) {
          expect(await _canvasPixel(tester), [0, 255, 0, 255]);
          await _show(
            tester,
            reader,
            theme: nextTheme,
            startsAtBeginning: true,
          );
          await tester.pumpAndSettle();
        }
        expect(await _canvasPixel(tester), [0, 0, 255, 255]);
        expect(await _canvasPixel(tester, x: 15, y: 5), [255, 255, 0, 255]);
        expect(reader.statuses.last.controller, same(controller));
        expect(controller.visiblePageIndex, page);
        // Suspension may release/revalidate view aliases as usual; it must not
        // rebuild native layouts/pictures merely to accept a canvas color.
        if (!suspended) {
          expect(controller.viewForPage(page), same(view));
          expect(
            tester.renderObject(find.byType(ForumBodyParagraphSurface).first),
            same(surface),
          );
        }
        expect(reader.positions, hasLength(reports + (suspended ? 1 : 0)));
        final actualPosition = reader.positions.last;
        expect(
          (
            actualPosition.anchor.nodeId,
            actualPosition.anchor.textOffset,
            actualPosition.anchor.formatVersion,
            actualPosition.anchor.textIdentity,
          ),
          (
            expectedPosition.nodeId,
            expectedPosition.textOffset,
            expectedPosition.formatVersion,
            expectedPosition.textIdentity,
          ),
        );
        expect(
          actualPosition.isReadOnlyCompatibilityRestore,
          compatibilityRestore,
        );
        expect(
          actualPosition.hasUserNavigated,
          suspended ? false : userNavigation,
        );
        expect(handle.cache.layoutBuildCount, builds);
        expect(handle.cache.pictureBuildCount, pictures);
        expect(reader.service.calls, 1);
        final activeView = controller.viewForPage(page);
        final acceptedReports = reader.positions.length;
        final activeSurface = tester.renderObject(
          find.byType(ForumBodyParagraphSurface).first,
        );
        await _show(tester, reader, theme: theme, startsAtBeginning: true);
        await tester.pumpAndSettle();
        expect(await _canvasPixel(tester), [0, 255, 0, 255]);
        expect(controller.viewForPage(page), same(activeView));
        expect(
          tester.renderObject(find.byType(ForumBodyParagraphSurface).first),
          same(activeSurface),
        );
        expect(reader.positions, hasLength(acceptedReports));
        expect(handle.cache.layoutBuildCount, builds);
        expect(handle.cache.pictureBuildCount, pictures);
        // Paragraph paint is a separate input: it must replace native objects,
        // even though the canvas and all geometric preferences are unchanged.
        await _show(
          tester,
          reader,
          theme: nextTheme.copyWith(
            colorScheme: nextTheme.colorScheme.copyWith(
              onSurface: const Color(0xff123456),
            ),
          ),
          startsAtBeginning: true,
        );
        await tester.pumpAndSettle();
        expect(reader.statuses.last.controller, isNot(same(controller)));
        expect(await _canvasPixel(tester, x: 5, y: 5), [18, 52, 86, 255]);
        expect(await _canvasPixel(tester, x: 15, y: 5), [255, 255, 0, 255]);
        final replacement = reader.owner.acquireCache();
        expect(replacement.cache, isNot(same(handle.cache)));
        expect(replacement.cache.layoutBuildCount, greaterThan(0));
        expect(handle.cache.layoutBuildCount, builds);
        replacement.release();
        expect(
          tester
              .widget<ForumBodyParagraphSurface>(
                find.byType(ForumBodyParagraphSurface).first,
              )
              .lease
              .content
              .style
              .textStyle
              .color,
          const Color(0xff123456),
        );
        handle.release();
        await _unmount(tester, reader);
      },
    );
  }
  testWidgets(
    'canvas paint neither extends a target deadline nor retries its failure',
    (tester) async {
      final reader = _Reader();
      var held = false;
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await gate.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      const policy = NovelReaderPaginationPerformancePolicy(
        targetPageWait: Duration(seconds: 5),
        backgroundIdle: Duration(seconds: 20),
      );
      final theme = ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xff00ff00),
      );
      await _show(
        tester,
        reader,
        theme: theme,
        scheduler: scheduler,
        performance: policy,
      );
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final reports = reader.positions.length;
      held = true;
      expect(controller.requestPage(8), true);
      await tester.pump(const Duration(seconds: 3));
      await _show(
        tester,
        reader,
        theme: theme.copyWith(scaffoldBackgroundColor: const Color(0xff0000ff)),
        scheduler: scheduler,
        performance: policy,
      );
      await tester.pump(const Duration(seconds: 3));
      final error = controller.error;
      expect(
        error,
        isA<NovelReaderPaginationException>().having(
          (e) => e.code,
          'code',
          'targetPageWaitExceeded',
        ),
      );
      expect(reader.statuses.last.controller, same(controller));
      expect(reader.positions, hasLength(reports));
      await _show(
        tester,
        reader,
        theme: theme.copyWith(scaffoldBackgroundColor: const Color(0xffff0000)),
        scheduler: scheduler,
        performance: policy,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(controller.error, same(error));
      expect(reader.statuses.last.controller, same(controller));
      expect(reader.positions, hasLength(reports));
      held = false;
      gate.complete();
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(reports));
      await _unmount(tester, reader);
    },
  );
  testWidgets(
    'withdrawing a consumed beginning does not revalidate live paint',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader, startsAtBeginning: true);
      await tester.pumpAndSettle();
      expect(reader.positions.single.pageIndex, 0);
      final controller = reader.statuses.last.controller;
      final count = reader.positions.length;
      final ready = reader.ready;
      reader.statuses.clear();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(
        reader.statuses.every(
          (status) =>
              status.phase == NovelReaderNativeHostPhase.reading &&
              !status.isRetainingPreviousLayout,
        ),
        isTrue,
      );
      expect(controller!.isSuspended, isFalse);
      expect(controller.isClosed, isFalse);
      expect(reader.positions, hasLength(count));
      expect(reader.ready, ready);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'duplicate activity notifications cannot extend a target deadline or implicitly retry its failure',
    (tester) async {
      final reader = _Reader();
      final signal = NativeReaderActivitySignal(true);
      addTearDown(signal.dispose);
      var held = false;
      final release = Completer<void>();
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await release.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      const performance = NovelReaderPaginationPerformancePolicy(
        targetPageWait: Duration(seconds: 5),
        backgroundIdle: Duration(seconds: 20),
      );
      await _show(
        tester,
        reader,
        activitySignal: signal,
        scheduler: scheduler,
        performance: performance,
      );
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      held = true;
      expect(controller.requestPage(8), isTrue);
      final revision = controller.navigationRevision;
      await tester.pump(const Duration(seconds: 3));
      signal.repeat();
      expect(controller.navigationRevision, revision);
      await tester.pump(const Duration(seconds: 3));
      expect(
        controller.error,
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'targetPageWaitExceeded',
        ),
      );
      final error = controller.error;
      signal.value = false;
      signal.value = true;
      held = false;
      release.complete();
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(controller.error, same(error));
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );
  testWidgets(
    'activity signal gates initial preparation and is borrowed until unmount',
    (tester) async {
      final reader = _Reader();
      final signal = NativeReaderActivitySignal(false);
      addTearDown(signal.dispose);
      await _show(tester, reader, activitySignal: signal);
      await tester.pumpAndSettle();
      expect(reader.service.calls, 0);
      expect(reader.owner.activeCacheHandles, 0);
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.inactive);
      signal.value = true;
      expect(reader.service.calls, 0);
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(1));
      expect(signal.isObserved, isTrue);
      await _unmount(tester, reader);
      expect(signal.isObserved, isFalse);
    },
  );

  testWidgets(
    'activity off/on without an inactive frame retires a pending target before resuming its Scope',
    (tester) async {
      final reader = _Reader();
      final signal = NativeReaderActivitySignal(true);
      addTearDown(signal.dispose);
      var held = false;
      final release = Completer<void>();
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await release.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      await _show(tester, reader, activitySignal: signal, scheduler: scheduler);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final before = reader.positions.last;
      held = true;
      expect(controller.requestPage(8), isTrue);
      signal.value = false;
      expect(controller.isSuspended, isTrue);
      expect(controller.hasPendingNavigation, isFalse);
      expect(controller.readyTarget, isNull);
      signal.value = true;
      expect(controller.isSuspended, isTrue);
      expect(reader.positions.last, same(before));
      held = false;
      release.complete();
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(controller.isSuspended, isFalse);
      expect(reader.positions.last.pageIndex, before.pageIndex);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'synchronous activity loss cancels deadlines before a one-hour first inactive frame',
    (tester) async {
      final reader = _Reader();
      final signal = NativeReaderActivitySignal(true);
      addTearDown(signal.dispose);
      var held = false;
      final release = Completer<void>();
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await release.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      const performance = NovelReaderPaginationPerformancePolicy();
      await _show(
        tester,
        reader,
        activitySignal: signal,
        scheduler: scheduler,
        performance: performance,
      );
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final reports = reader.positions.length;
      held = true;
      expect(controller.requestPage(8), isTrue);
      signal.value = false;
      expect(controller.isSuspended, isTrue);
      await tester.pump(const Duration(hours: 1));
      expect(controller.error, isNull);
      expect(reader.positions, hasLength(reports));
      held = false;
      release.complete();
      await tester.pumpAndSettle();
      expect(controller.readyTarget, isNull);
      signal.value = true;
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(controller.error, isNull);
      expect(
        reader.positions.every((position) => !position.hasUserNavigated),
        isTrue,
      );
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'a created layout hidden before its first viewport cannot start source work',
    (tester) async {
      final reader = _Reader();
      final signal = NativeReaderActivitySignal(true);
      addTearDown(signal.dispose);
      await _show(tester, reader, activitySignal: signal);
      expect(reader.owner.activeCacheHandles, 1);
      expect(find.byType(ForumBodyTextPageSurface), findsNothing);
      signal.value = false;
      await tester.pump(const Duration(hours: 1));
      final cache = reader.owner.acquireCache();
      expect(cache.cache.layoutBuildCount, 0);
      cache.release();
      expect(reader.positions, isEmpty);
      expect(reader.ready, 0);
      signal.value = true;
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(1));
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'activity resume validates hidden font and geometry changes before any old controller can run',
    (tester) async {
      final reader = _Reader();
      final signal = NativeReaderActivitySignal(true);
      addTearDown(signal.dispose);
      await _show(tester, reader, activitySignal: signal);
      await tester.pumpAndSettle();
      final old = reader.statuses.last.controller!;
      final before = reader.positions.last;
      signal.value = false;
      reader.fonts.notifyListeners();
      signal.value = true;
      expect(old.isSuspended || old.isClosed, isTrue);
      expect(reader.positions.last, same(before));
      await _show(
        tester,
        reader,
        activitySignal: signal,
        width: 60,
        preferences: reader.preferences.copyWith(fontSize: 20),
      );
      await tester.pumpAndSettle();
      final next = reader.statuses.last.controller!;
      expect(next, isNot(same(old)));
      expect(next.snapshot!.width, 60);
      expect(reader.positions.last.anchor.textOffset, before.anchor.textOffset);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'activity retirement consumes navigation still waiting for pure preparation',
    (tester) async {
      final reader = _Reader();
      reader.service.gate = Completer<void>();
      final signal = NativeReaderActivitySignal(true);
      addTearDown(signal.dispose);
      final origin = reader.semantic.sourceProvenance!.origins.first;
      final navigation = NovelReaderAnchorNavigationRequest(
        requestId: 1,
        anchor: NovelReaderTextAnchor(
          episodeId: reader.episodeId,
          nodeId: origin.nodeId,
          textOffset: 125,
          formatVersion: 1,
          textIdentity: NovelReaderAnchorFormat.textIdentity(origin.text),
        ),
      );
      await _show(
        tester,
        reader,
        activitySignal: signal,
        anchorNavigation: navigation,
      );
      await tester.pumpAndSettle();
      signal.value = false;
      signal.value = true;
      reader.service.gate!.complete();
      await tester.pumpAndSettle();
      expect(reader.anchorResults, [
        (navigation, NovelReaderNavigationOutcome.retired),
      ]);
      expect(reader.positions.single.hasUserNavigated, isFalse);
      expect(reader.positions.single.anchor.textOffset, 73);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'new navigation submitted while inactive remains an explicit new input on return',
    (tester) async {
      final reader = _Reader();
      final signal = NativeReaderActivitySignal(true);
      addTearDown(signal.dispose);
      await _show(tester, reader, activitySignal: signal);
      await tester.pumpAndSettle();
      signal.value = false;
      final origin = reader.semantic.sourceProvenance!.origins.first;
      final navigation = NovelReaderAnchorNavigationRequest(
        requestId: 2,
        anchor: NovelReaderTextAnchor(
          episodeId: reader.episodeId,
          nodeId: origin.nodeId,
          textOffset: 125,
          formatVersion: 1,
          textIdentity: NovelReaderAnchorFormat.textIdentity(origin.text),
        ),
      );
      await _show(
        tester,
        reader,
        activitySignal: signal,
        anchorNavigation: navigation,
      );
      await tester.pumpAndSettle();
      expect(reader.anchorResults, isEmpty);
      signal.value = true;
      await tester.pumpAndSettle();
      expect(reader.anchorResults, [
        (navigation, NovelReaderNavigationOutcome.arrived),
      ]);
      expect(reader.positions.last.anchor.textOffset, 125);
      expect(reader.positions.last.hasUserNavigated, isTrue);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'replacing activity listenable detaches the old signal without restarting an unchanged Scope',
    (tester) async {
      final reader = _Reader();
      final old = NativeReaderActivitySignal(true);
      final next = NativeReaderActivitySignal(true);
      addTearDown(old.dispose);
      addTearDown(next.dispose);
      await _show(tester, reader, activitySignal: old);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      await _show(tester, reader, activitySignal: next);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(old.isObserved, isFalse);
      expect(next.isObserved, isTrue);
      old.value = false;
      expect(controller.isSuspended, isFalse);
      next.value = false;
      expect(controller.isSuspended, isTrue);
      await _unmount(tester, reader);
      expect(next.isObserved, isFalse);
      next.value = true;
    },
  );

  testWidgets('widget activity and synchronous signal must both allow work', (
    tester,
  ) async {
    final reader = _Reader();
    final signal = NativeReaderActivitySignal(true);
    addTearDown(signal.dispose);
    await _show(tester, reader, active: false, activitySignal: signal);
    signal.value = false;
    signal.value = true;
    await tester.pumpAndSettle();
    expect(reader.service.calls, 0);
    await _show(tester, reader, activitySignal: signal);
    await tester.pumpAndSettle();
    final controller = reader.statuses.last.controller!;
    signal.value = false;
    await _show(tester, reader, active: false, activitySignal: signal);
    signal.value = true;
    expect(controller.isSuspended, isTrue);
    await tester.pumpAndSettle();
    expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.inactive);
    await _show(tester, reader, activitySignal: signal);
    await tester.pumpAndSettle();
    expect(reader.statuses.last.controller, same(controller));
    expect(reader.service.calls, 1);
    await _unmount(tester, reader);
  });

  testWidgets(
    'Host forwards live boundary hints and verifies actual end navigation only on accepted release',
    (tester) async {
      final reader = _Reader(html: '<p>abcd</p>');
      final navigation = NovelReaderPagedNavigationController();
      addTearDown(navigation.dispose);
      final confirmations = <bool>[];
      final edges = <NovelReaderChapterEdge>[];
      await _show(
        tester,
        reader,
        navigation: navigation,
        previousTitle: 'previous',
        nextTitle: 'next',
        onChapter: (edge) {
          edges.add(edge);
          confirmations.add(navigation.confirmChapterEndNavigation());
          return true;
        },
      );
      await tester.pumpAndSettle();
      final initial = reader.positions.length;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(reader.chapterHints.last!.isReadyToCommit, isTrue);
      expect(reader.chapterHints.last!.chapterTitle, 'next');
      expect(reader.positions, hasLength(initial));
      expect(edges, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(edges, [NovelReaderChapterEdge.end]);
      expect(confirmations, [true]);
      expect(reader.positions.last.hasUserNavigated, isTrue);
      expect(reader.chapterHints.last, isNull);
      await _unmount(tester, reader);
    },
  );

  for (final interruption in [
    'hidden',
    'font',
    'owner',
    'authority',
    'retry',
    'geometry',
    'seek',
    'titles',
    'inflight',
    'policy',
  ]) {
    testWidgets(
      'Host $interruption clears a shell hint and retires its chapter release',
      (tester) async {
        final reader = _Reader(html: '<p>abcd</p>');
        final navigation = NovelReaderPagedNavigationController();
        addTearDown(navigation.dispose);
        final edges = <NovelReaderChapterEdge>[];
        bool onChapter(NovelReaderChapterEdge edge) {
          edges.add(edge);
          return true;
        }

        await _show(
          tester,
          reader,
          navigation: navigation,
          nextTitle: 'next',
          onChapter: onChapter,
        );
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(PageView)),
        );
        await gesture.moveBy(const Offset(-80, 0));
        await tester.pumpAndSettle();
        expect(reader.chapterHints.last!.isReadyToCommit, isTrue);
        if (interruption == 'owner') {
          reader.owner.dispose();
        } else if (interruption == 'font') {
          reader.fonts.notifyListeners();
        } else {
          final status = reader.statuses.last;
          await _show(
            tester,
            reader,
            navigation: navigation,
            onChapter: onChapter,
            active: interruption != 'hidden',
            width: interruption == 'geometry' ? 60 : 100,
            authority: interruption == 'authority'
                ? Object()
                : reader.authority,
            retry: interruption == 'retry' ? 1 : 0,
            nextTitle: interruption == 'titles' ? 'changed' : 'next',
            chapterInFlight: interruption == 'inflight',
            chapterPolicy: interruption == 'policy'
                ? const NovelReaderChapterTurnPolicy(minCommitDistance: 200)
                : const NovelReaderChapterTurnPolicy(),
            seek: interruption == 'seek'
                ? NovelReaderPageSeekRequest(
                    requestId: 1,
                    episodeId: reader.episodeId,
                    paginationKey: status.controller!.paginationKey,
                    pageIndex: 0,
                  )
                : null,
          );
        }
        await tester.pumpAndSettle();
        expect(reader.chapterHints.last, isNull);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(edges, isEmpty);
        await _unmount(tester, reader);
      },
    );
  }

  testWidgets(
    'Host cannot hint or switch when the shell has no chapter action',
    (tester) async {
      final reader = _Reader(html: '<p>abcd</p>');
      await _show(tester, reader, nextTitle: 'next');
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(
        reader.chapterHints.whereType<NovelReaderChapterTurnHint>(),
        isEmpty,
      );
      await _unmount(tester, reader);
    },
  );

  for (final replacement in ['entry', 'retry']) {
    testWidgets(
      '$replacement retires a semantic intent still waiting for pure preparation',
      (tester) async {
        final reader = _Reader();
        reader.service.gate = Completer<void>();
        final origin = reader.semantic.sourceProvenance!.origins.first;
        final navigation = NovelReaderAnchorNavigationRequest(
          requestId: 1,
          anchor: NovelReaderTextAnchor(
            episodeId: reader.episodeId,
            nodeId: origin.nodeId,
            textOffset: 125,
            formatVersion: 1,
            textIdentity: NovelReaderAnchorFormat.textIdentity(origin.text),
          ),
        );
        final entry = NovelReaderChapterEntryRequest(
          requestId: 1,
          episodeId: reader.episodeId,
          edge: NovelReaderChapterEdge.end,
        );
        await _show(tester, reader, anchorNavigation: navigation);
        await tester.pumpAndSettle();
        expect(reader.positions, isEmpty);
        await _show(
          tester,
          reader,
          anchorNavigation: navigation,
          entry: replacement == 'entry' ? entry : null,
          retry: replacement == 'retry' ? 1 : 0,
        );
        await tester.pumpAndSettle();
        expect(reader.anchorResults, [
          (navigation, NovelReaderNavigationOutcome.retired),
        ]);
        reader.service.gate!.complete();
        await tester.pumpAndSettle();
        expect(reader.positions, hasLength(1));
        expect(reader.positions.single.anchor.textOffset, isNot(125));
        expect(reader.anchorResults, hasLength(1));
        if (replacement == 'entry') {
          expect(
            reader.positions.single.appliedChapterEntry,
            NovelReaderChapterEdge.end,
          );
          expect(reader.appliedEntries, [entry]);
        } else {
          expect(reader.positions.single.anchor.textOffset, 73);
          expect(reader.positions.single.hasUserNavigated, isFalse);
        }
        await _unmount(tester, reader);
      },
    );
  }

  for (final change in ['hide', 'reflow']) {
    testWidgets(
      'pending end entry survives $change without an early completion',
      (tester) async {
        final reader = _Reader();
        var held = true;
        final gate = Completer<void>();
        final scheduler = NovelReaderNativeWorkScheduler(
          nextFrame: () async {
            if (held) {
              await gate.future;
            } else {
              await WidgetsBinding.instance.endOfFrame;
            }
          },
        );
        final entry = NovelReaderChapterEntryRequest(
          requestId: 1,
          episodeId: reader.episodeId,
          edge: NovelReaderChapterEdge.end,
        );
        await _show(tester, reader, scheduler: scheduler, entry: entry);
        await tester.pumpAndSettle();
        final original = reader.statuses.last.controller;
        await _show(
          tester,
          reader,
          scheduler: scheduler,
          entry: entry,
          active: change != 'hide',
          preferences: change == 'reflow'
              ? reader.preferences.copyWith(fontSize: 20)
              : null,
        );
        await tester.pumpAndSettle();
        if (change == 'hide') {
          await _show(tester, reader, scheduler: scheduler, entry: entry);
          await tester.pumpAndSettle();
          expect(reader.statuses.last.controller, same(original));
        }
        expect(reader.positions, isEmpty);
        expect(reader.appliedEntries, isEmpty);
        expect(reader.retiredEntries, isEmpty);
        held = false;
        gate.complete();
        await tester.pumpAndSettle();
        expect(reader.appliedEntries, [entry]);
        expect(reader.retiredEntries, isEmpty);
        expect(
          reader.positions.single.appliedChapterEntry,
          NovelReaderChapterEdge.end,
        );
        expect(
          reader.positions.single.pageIndex,
          reader.positions.single.pageCount - 1,
        );
        await _unmount(tester, reader);
      },
    );
  }

  testWidgets(
    'resuming a failed pending end entry does not implicitly retry the source',
    (tester) async {
      final reader = _Reader(
        html:
            '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p><div style="position:absolute">unsupported</div>',
      );
      final entry = NovelReaderChapterEntryRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        edge: NovelReaderChapterEdge.end,
      );
      await _show(tester, reader, entry: entry);
      await tester.pumpAndSettle();
      final original = reader.statuses.last.controller!;
      final error = original.error;
      final snapshot = original.snapshot;
      await _show(tester, reader, entry: entry, active: false);
      await tester.pumpAndSettle();
      await _show(tester, reader, entry: entry);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(original));
      expect(original.error, same(error));
      expect(original.snapshot, same(snapshot));
      expect(reader.positions, isEmpty);
      expect(reader.appliedEntries, isEmpty);
      expect(reader.retiredEntries, isEmpty);
      await _unmount(tester, reader);
    },
  );

  for (final edge in NovelReaderChapterEdge.values) {
    testWidgets(
      '$edge applies once only at its mounted edge and does not replay after removal or reflow',
      (tester) async {
        final reader = _Reader();
        final entry = NovelReaderChapterEntryRequest(
          requestId: 1,
          episodeId: reader.episodeId,
          edge: edge,
        );
        await _show(tester, reader, entry: entry);
        await tester.pumpAndSettle();
        final position = reader.positions.single;
        expect(position.appliedChapterEntry, edge);
        expect(
          position.pageIndex,
          edge == NovelReaderChapterEdge.start ? 0 : position.pageCount - 1,
        );
        expect(reader.appliedEntries, [entry]);
        expect(reader.retiredEntries, isEmpty);
        final controller = reader.statuses.last.controller;
        await _show(tester, reader);
        await tester.pumpAndSettle();
        expect(reader.statuses.last.controller, same(controller));
        expect(reader.positions, hasLength(1));
        await _show(
          tester,
          reader,
          entry: entry,
          preferences: reader.preferences.copyWith(fontSize: 20),
        );
        await tester.pumpAndSettle();
        expect(reader.appliedEntries, [entry]);
        expect(reader.retiredEntries, isEmpty);
        expect(reader.positions.last.appliedChapterEntry, isNull);
        expect(
          reader.positions.last.anchor.textOffset,
          position.anchor.textOffset,
        );
        await _unmount(tester, reader);
      },
    );

    testWidgets(
      '$edge callback may navigate immediately without reusing entry proof',
      (tester) async {
        final reader = _Reader();
        final navigation = NovelReaderPagedNavigationController();
        addTearDown(navigation.dispose);
        final commands = <bool>[];
        reader.onEntryApplied = () => commands.add(
          edge == NovelReaderChapterEdge.start
              ? navigation.turnNext()
              : navigation.turnPrevious(),
        );
        final entry = NovelReaderChapterEntryRequest(
          requestId: 1,
          episodeId: reader.episodeId,
          edge: edge,
        );
        await _show(tester, reader, entry: entry, navigation: navigation);
        await tester.pumpAndSettle();
        expect(commands, [true]);
        expect(reader.appliedEntries, [entry]);
        expect(reader.positions, hasLength(2));
        expect(reader.positions.first.appliedChapterEntry, edge);
        expect(reader.positions.last.appliedChapterEntry, isNull);
        expect(reader.positions.last.hasUserNavigated, isTrue);
        await _unmount(tester, reader);
      },
    );
  }

  testWidgets(
    'cancelled search before first paint restores the original pending end entry',
    (tester) async {
      final reader = _Reader();
      final gate = Completer<void>();
      var held = true;
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await gate.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      final entry = NovelReaderChapterEntryRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        edge: NovelReaderChapterEdge.end,
      );
      final origin = reader.semantic.sourceProvenance!.origins.first;
      final navigation = NovelReaderAnchorNavigationRequest(
        requestId: 1,
        anchor: NovelReaderTextAnchor(
          episodeId: reader.episodeId,
          nodeId: origin.nodeId,
          textOffset: 125,
          formatVersion: 1,
          textIdentity: NovelReaderAnchorFormat.textIdentity(origin.text),
        ),
      );
      await _show(
        tester,
        reader,
        scheduler: scheduler,
        entry: entry,
        anchorNavigation: navigation,
      );
      await tester.pumpAndSettle();
      expect(reader.positions, isEmpty);
      await _show(tester, reader, scheduler: scheduler, entry: entry);
      await tester.pumpAndSettle();
      expect(reader.retiredEntries, isEmpty);
      held = false;
      gate.complete();
      await tester.pumpAndSettle();
      expect(reader.appliedEntries, [entry]);
      expect(
        reader.positions.single.appliedChapterEntry,
        NovelReaderChapterEdge.end,
      );
      expect(
        reader.positions.single.pageIndex,
        reader.positions.single.pageCount - 1,
      );
      expect(reader.anchorResults, [
        (navigation, NovelReaderNavigationOutcome.retired),
      ]);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'an unavailable search before first paint applies only its original bootstrap end entry',
    (tester) async {
      final reader = _Reader(html: '<p>a\u0301b</p>');
      final origin = reader.semantic.sourceProvenance!.origins.first;
      final entry = NovelReaderChapterEntryRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        edge: NovelReaderChapterEdge.end,
      );
      final navigation = NovelReaderAnchorNavigationRequest(
        requestId: 1,
        anchor: NovelReaderTextAnchor(
          episodeId: reader.episodeId,
          nodeId: origin.nodeId,
          textOffset: 1,
          formatVersion: 1,
          textIdentity: NovelReaderAnchorFormat.textIdentity(origin.text),
        ),
      );
      await _show(tester, reader, entry: entry, anchorNavigation: navigation);
      await tester.pumpAndSettle();
      expect(reader.anchorResults, [
        (navigation, NovelReaderNavigationOutcome.unavailable),
      ]);
      expect(reader.appliedEntries, [entry]);
      expect(reader.retiredEntries, isEmpty);
      expect(
        reader.positions.single.appliedChapterEntry,
        NovelReaderChapterEdge.end,
      );
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'a newer entry retires an unresolved old entry and late old frames cannot apply it',
    (tester) async {
      final reader = _Reader();
      var held = true;
      final gate = Completer<void>();
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await gate.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      final old = NovelReaderChapterEntryRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        edge: NovelReaderChapterEdge.end,
      );
      final next = NovelReaderChapterEntryRequest(
        requestId: 2,
        episodeId: reader.episodeId,
        edge: NovelReaderChapterEdge.start,
      );
      await _show(tester, reader, scheduler: scheduler, entry: old);
      await tester.pumpAndSettle();
      await _show(tester, reader, scheduler: scheduler, entry: next);
      await tester.pumpAndSettle();
      expect(reader.retiredEntries, [old]);
      expect(reader.appliedEntries, isEmpty);
      held = false;
      gate.complete();
      await tester.pumpAndSettle();
      expect(reader.appliedEntries, [next]);
      expect(reader.retiredEntries, [old]);
      expect(
        reader.positions.single.appliedChapterEntry,
        NovelReaderChapterEdge.start,
      );
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'entry identity includes the edge even when serial and chapter are reused',
    (tester) async {
      final reader = _Reader();
      final end = NovelReaderChapterEntryRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        edge: NovelReaderChapterEdge.end,
      );
      final start = NovelReaderChapterEntryRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        edge: NovelReaderChapterEdge.start,
      );
      await _show(tester, reader, entry: end);
      await tester.pumpAndSettle();
      await _show(tester, reader, entry: start);
      await tester.pumpAndSettle();
      expect(reader.appliedEntries, [end, start]);
      expect(reader.retiredEntries, isEmpty);
      expect(reader.positions.last.pageIndex, 0);
      expect(
        reader.positions.last.appliedChapterEntry,
        NovelReaderChapterEdge.start,
      );
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'entry for another chapter leaves the active controller and its position unchanged',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller;
      final point = reader.positions.single;
      await _show(
        tester,
        reader,
        entry: const NovelReaderChapterEntryRequest(
          requestId: 1,
          episodeId: 'other',
          edge: NovelReaderChapterEdge.end,
        ),
      );
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(reader.positions, [point]);
      expect(reader.appliedEntries, isEmpty);
      expect(reader.retiredEntries, isEmpty);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'reading a failed end-entry prefix retires the entry without claiming the final edge',
    (tester) async {
      final reader = _Reader(
        html:
            '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p><div style="position:absolute">unsupported</div>',
      );
      final entry = NovelReaderChapterEntryRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        edge: NovelReaderChapterEdge.end,
      );
      await _show(tester, reader, entry: entry);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final error = controller.error;
      expect(reader.positions, isEmpty);
      final seek = NovelReaderPageSeekRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        paginationKey: controller.paginationKey,
        pageIndex: 0,
      );
      await _show(tester, reader, entry: entry, seek: seek);
      await tester.pumpAndSettle();
      expect(reader.appliedEntries, isEmpty);
      expect(reader.retiredEntries, [entry]);
      expect(reader.positions.single.appliedChapterEntry, isNull);
      expect(reader.positions.single.isPageCountFinal, isFalse);
      expect(controller.error, same(error));
      await _show(tester, reader, entry: entry, retry: 1);
      await tester.pumpAndSettle();
      expect(reader.retiredEntries, [entry]);
      expect(reader.appliedEntries, isEmpty);
      expect(reader.positions.last.pageIndex, 0);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'retiring the owner in a position callback suppresses deferred entry completion',
    (tester) async {
      final reader = _Reader();
      reader.onPosition = (_) => reader.owner.dispose();
      final entry = NovelReaderChapterEntryRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        edge: NovelReaderChapterEdge.end,
      );
      await _show(tester, reader, entry: entry);
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(1));
      expect(reader.appliedEntries, isEmpty);
      expect(reader.retiredEntries, isEmpty);
      expect(reader.owner.activeCacheHandles, 0);
      await _unmount(tester, reader);
    },
  );

  for (final edge in NovelReaderChapterEdge.values) {
    testWidgets(
      'a semantic request superseding $edge cannot falsely apply that chapter entry',
      (tester) async {
        final reader = _Reader();
        final origin = reader.semantic.sourceProvenance!.origins.first;
        final navigation = NovelReaderAnchorNavigationRequest(
          requestId: 1,
          anchor: NovelReaderTextAnchor(
            episodeId: reader.episodeId,
            nodeId: origin.nodeId,
            textOffset: 125,
            formatVersion: 1,
            textIdentity: NovelReaderAnchorFormat.textIdentity(origin.text),
          ),
        );
        final entry = NovelReaderChapterEntryRequest(
          requestId: 1,
          episodeId: reader.episodeId,
          edge: edge,
        );
        await _show(tester, reader, entry: entry, anchorNavigation: navigation);
        await tester.pumpAndSettle();
        expect(reader.positions.single.anchor.textOffset, 125);
        expect(reader.appliedEntries, isEmpty);
        expect(reader.retiredEntries, [entry]);
        await _unmount(tester, reader);
      },
    );
  }
  testWidgets(
    'a missing anchor completes as unavailable while preserving the healthy mounted position',
    (tester) async {
      final reader = _Reader(html: '<p>a\u0301b</p>');
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final before = reader.positions.last;
      final request = NovelReaderAnchorNavigationRequest(
        requestId: 1,
        anchor: before.anchor.copyWith(textOffset: 1),
      );
      await _show(tester, reader, anchorNavigation: request);
      await tester.pumpAndSettle();
      await _show(tester, reader, anchorNavigation: request);
      await tester.pumpAndSettle();
      expect(reader.anchorResults, [
        (request, NovelReaderNavigationOutcome.unavailable),
      ]);
      expect(reader.positions, [before]);
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.reading);
      expect(reader.statuses.last.controller!.error, isNull);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'semantic navigation can hit or reject a finite paused prefix without retrying its source',
    (tester) async {
      final reader = _Reader(
        html:
            '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p><div style="position:absolute">unsupported</div><p>outside</p>',
      );
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final error = controller.error;
      final prefix = controller.snapshot;
      final hit = NovelReaderAnchorNavigationRequest(
        requestId: 1,
        anchor: reader.positions.last.anchor.copyWith(textOffset: 125),
      );
      await _show(tester, reader, anchorNavigation: hit);
      await tester.pumpAndSettle();
      final actual = reader.positions.last;
      expect(actual.anchor.textOffset, 125);
      expect(reader.anchorResults, [
        (hit, NovelReaderNavigationOutcome.arrived),
      ]);
      final outside = reader.semantic.sourceProvenance!.origins.last;
      final miss = NovelReaderAnchorNavigationRequest(
        requestId: 2,
        anchor: NovelReaderTextAnchor(
          episodeId: reader.episodeId,
          nodeId: outside.nodeId,
          textOffset: 1,
          formatVersion: 1,
          textIdentity: NovelReaderAnchorFormat.textIdentity(outside.text),
        ),
      );
      await _show(tester, reader, anchorNavigation: miss);
      await tester.pumpAndSettle();
      expect(reader.anchorResults.last, (
        miss,
        NovelReaderNavigationOutcome.unavailable,
      ));
      expect(reader.positions.last, same(actual));
      expect(controller.error, same(error));
      expect(controller.snapshot, same(prefix));
      expect(reader.statuses.last.controller, same(controller));
      expect(controller.snapshot!.isComplete, isFalse);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'semantic navigation timeout finishes once and ignores its late target',
    (tester) async {
      final reader = _Reader();
      var held = false;
      final gate = Completer<void>();
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await gate.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      const policy = NovelReaderPaginationPerformancePolicy(
        targetPageWait: Duration(seconds: 1),
      );
      await _show(tester, reader, scheduler: scheduler, performance: policy);
      await tester.pumpAndSettle();
      final before = reader.positions.last;
      final request = NovelReaderAnchorNavigationRequest(
        requestId: 1,
        anchor: before.anchor.copyWith(textOffset: 125),
      );
      held = true;
      await _show(
        tester,
        reader,
        scheduler: scheduler,
        performance: policy,
        anchorNavigation: request,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(reader.anchorResults, [
        (request, NovelReaderNavigationOutcome.unavailable),
      ]);
      expect(reader.positions, [before]);
      held = false;
      gate.complete();
      await tester.pumpAndSettle();
      expect(reader.anchorResults, hasLength(1));
      expect(reader.positions, [before]);
      await _unmount(tester, reader);
    },
  );

  testWidgets('owner handoff suppresses the old semantic request completion', (
    tester,
  ) async {
    final old = _Reader();
    var held = false;
    final gate = Completer<void>();
    final scheduler = NovelReaderNativeWorkScheduler(
      nextFrame: () async {
        if (held) {
          await gate.future;
        } else {
          await WidgetsBinding.instance.endOfFrame;
        }
      },
    );
    await _show(tester, old, scheduler: scheduler);
    await tester.pumpAndSettle();
    final request = NovelReaderAnchorNavigationRequest(
      requestId: 1,
      anchor: old.positions.last.anchor.copyWith(textOffset: 125),
    );
    held = true;
    await _show(tester, old, scheduler: scheduler, anchorNavigation: request);
    await tester.pumpAndSettle();
    final next = _Reader(episodeId: 'next');
    await _show(tester, next);
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(old.anchorResults, isEmpty);
    expect(next.anchorResults, isEmpty);
    expect(old.positions, hasLength(1));
    expect(next.positions, hasLength(1));
    expect(old.owner.activeCacheHandles, 0);
    await _unmount(tester, next);
  });

  testWidgets(
    'initial semantic navigation confirms its actual anchor once and ignores legacy page hints',
    (tester) async {
      final reader = _Reader();
      final origin = reader.semantic.sourceProvenance!.origins.first;
      final anchor = NovelReaderTextAnchor(
        episodeId: reader.episodeId,
        nodeId: origin.nodeId,
        textOffset: 125,
        formatVersion: 1,
        textIdentity: NovelReaderAnchorFormat.textIdentity(origin.text),
        pageIndex: 99,
        progressPercent: .99,
        isProgressPercentValid: true,
      );
      final request = NovelReaderAnchorNavigationRequest(
        requestId: 1,
        anchor: anchor,
      );
      await _show(tester, reader, anchorNavigation: request);
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(1));
      expect(reader.positions.single.anchor.textOffset, 125);
      expect(reader.positions.single.hasUserNavigated, isTrue);
      expect(reader.anchorResults, [
        (request, NovelReaderNavigationOutcome.arrived),
      ]);
      await _show(
        tester,
        reader,
        anchorNavigation: NovelReaderAnchorNavigationRequest(
          requestId: 1,
          anchor: anchor.copyWith(pageIndex: 7, progressPercent: .2),
        ),
      );
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(1));
      expect(reader.anchorResults, hasLength(1));
      await _unmount(tester, reader);
    },
  );

  for (final first in ['page', 'anchor']) {
    testWidgets(
      'latest $first replacement owns the single navigation lane and removing older input cannot cancel it',
      (tester) async {
        final reader = _Reader();
        var held = false;
        final gate = Completer<void>();
        final scheduler = NovelReaderNativeWorkScheduler(
          nextFrame: () async {
            if (held) {
              await gate.future;
            } else {
              await WidgetsBinding.instance.endOfFrame;
            }
          },
        );
        await _show(tester, reader, scheduler: scheduler);
        await tester.pumpAndSettle();
        final before = reader.positions.last;
        final seek = NovelReaderPageSeekRequest(
          requestId: 1,
          episodeId: reader.episodeId,
          paginationKey: before.paginationKey,
          pageIndex: 7,
        );
        final navigation = NovelReaderAnchorNavigationRequest(
          requestId: 1,
          anchor: before.anchor.copyWith(textOffset: 125),
        );
        held = true;
        await _show(
          tester,
          reader,
          scheduler: scheduler,
          seek: first == 'page' ? seek : null,
          anchorNavigation: first == 'anchor' ? navigation : null,
        );
        await tester.pumpAndSettle();
        await _show(
          tester,
          reader,
          scheduler: scheduler,
          seek: seek,
          anchorNavigation: navigation,
        );
        await tester.pumpAndSettle();
        // Remove the older input while the newer request is still waiting.
        await _show(
          tester,
          reader,
          scheduler: scheduler,
          seek: first == 'anchor' ? seek : null,
          anchorNavigation: first == 'page' ? navigation : null,
        );
        await tester.pumpAndSettle();
        expect(reader.positions, [before]);
        held = false;
        gate.complete();
        await tester.pumpAndSettle();
        if (first == 'page') {
          expect(reader.seekResults, [
            (seek, NovelReaderNavigationOutcome.retired),
          ]);
          expect(reader.anchorResults, [
            (navigation, NovelReaderNavigationOutcome.arrived),
          ]);
          expect(reader.positions.last.anchor.textOffset, 125);
        } else {
          expect(reader.anchorResults, [
            (navigation, NovelReaderNavigationOutcome.retired),
          ]);
          expect(reader.seekResults, [
            (seek, NovelReaderNavigationOutcome.arrived),
          ]);
          expect(reader.positions.last.pageIndex, 7);
        }
        expect(reader.positions, hasLength(2));
        expect(reader.service.calls, 1);
        await _unmount(tester, reader);
      },
    );
  }

  testWidgets(
    'simultaneous new inputs choose the semantic request without reviving the ignored page seek',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final before = reader.positions.last;
      final seek = NovelReaderPageSeekRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        paginationKey: before.paginationKey,
        pageIndex: 7,
      );
      final navigation = NovelReaderAnchorNavigationRequest(
        requestId: 1,
        anchor: before.anchor.copyWith(textOffset: 125),
      );
      await _show(tester, reader, seek: seek, anchorNavigation: navigation);
      await tester.pumpAndSettle();
      expect(reader.positions.last.anchor.textOffset, 125);
      expect(reader.anchorResults, [
        (navigation, NovelReaderNavigationOutcome.arrived),
      ]);
      expect(reader.seekResults, isEmpty);
      await _show(tester, reader, seek: seek);
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(2));
      expect(reader.seekResults, isEmpty);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'unavailable initial anchor reports failure even when explicit chapter-start fallback is navigable',
    (tester) async {
      final reader = _Reader(html: '<p>a\u0301b</p>');
      final origin = reader.semantic.sourceProvenance!.origins.first;
      final navigation = NovelReaderAnchorNavigationRequest(
        requestId: 1,
        anchor: NovelReaderTextAnchor(
          episodeId: reader.episodeId,
          nodeId: origin.nodeId,
          textOffset: 1,
          formatVersion: 1,
          textIdentity: NovelReaderAnchorFormat.textIdentity(origin.text),
        ),
      );
      await _show(
        tester,
        reader,
        anchorNavigation: navigation,
        startsAtBeginning: true,
      );
      await tester.pumpAndSettle();
      expect(reader.anchorResults, [
        (navigation, NovelReaderNavigationOutcome.unavailable),
      ]);
      expect(reader.positions, hasLength(1));
      expect(reader.positions.single.anchor.textOffset, 0);
      expect(reader.positions.single.hasUserNavigated, isTrue);
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.reading);
      expect(reader.statuses.last.controller!.error, isNull);
      await _unmount(tester, reader);
    },
  );

  for (final replacement in ['remove', 'hide', 'reflow']) {
    testWidgets(
      '$replacement retires pending semantic navigation without replaying its target',
      (tester) async {
        final reader = _Reader();
        var held = false;
        final gate = Completer<void>();
        final scheduler = NovelReaderNativeWorkScheduler(
          nextFrame: () async {
            if (held) {
              await gate.future;
            } else {
              await WidgetsBinding.instance.endOfFrame;
            }
          },
        );
        await _show(tester, reader, scheduler: scheduler);
        await tester.pumpAndSettle();
        final before = reader.positions.last;
        final navigation = NovelReaderAnchorNavigationRequest(
          requestId: 1,
          anchor: before.anchor.copyWith(textOffset: 125),
        );
        held = true;
        await _show(
          tester,
          reader,
          scheduler: scheduler,
          anchorNavigation: navigation,
        );
        await tester.pumpAndSettle();
        await _show(
          tester,
          reader,
          scheduler: scheduler,
          anchorNavigation: replacement == 'remove' ? null : navigation,
          active: replacement != 'hide',
          preferences: replacement == 'reflow'
              ? reader.preferences.copyWith(fontSize: 20)
              : null,
        );
        await tester.pumpAndSettle();
        expect(reader.anchorResults, [
          (navigation, NovelReaderNavigationOutcome.retired),
        ]);
        held = false;
        gate.complete();
        await tester.pumpAndSettle();
        if (replacement == 'hide') {
          await _show(
            tester,
            reader,
            scheduler: scheduler,
            anchorNavigation: navigation,
          );
          await tester.pumpAndSettle();
        }
        expect(
          reader.positions.last.anchor.textOffset,
          before.anchor.textOffset,
        );
        expect(reader.anchorResults, hasLength(1));
        if (replacement != 'remove') {
          expect(reader.positions.last.hasUserNavigated, isFalse);
        }
        await _unmount(tester, reader);
      },
    );
  }
  testWidgets(
    'a paused source still accepts a seek within its verified readable prefix',
    (tester) async {
      final reader = _Reader(
        html:
            '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p><div style="position:absolute">unsupported</div>',
      );
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final error = controller.error;
      final seek = NovelReaderPageSeekRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        paginationKey: reader.positions.last.paginationKey,
        pageIndex: 7,
      );
      await _show(tester, reader, seek: seek);
      await tester.pumpAndSettle();
      expect(reader.positions.last.pageIndex, 7);
      expect(reader.positions.last.hasUserNavigated, isTrue);
      expect(reader.seekResults, [(seek, NovelReaderPageSeekOutcome.arrived)]);
      expect(controller.error, same(error));
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.paused);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'removing an already completed seek cannot cancel newer navigation',
    (tester) async {
      final reader = _Reader();
      var held = false;
      final gate = Completer<void>();
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await gate.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      await _show(tester, reader, scheduler: scheduler);
      await tester.pumpAndSettle();
      final seek = NovelReaderPageSeekRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        paginationKey: reader.positions.last.paginationKey,
        pageIndex: 7,
      );
      await _show(tester, reader, scheduler: scheduler, seek: seek);
      await tester.pumpAndSettle();
      expect(reader.seekResults, [(seek, NovelReaderPageSeekOutcome.arrived)]);
      held = true;
      reader.statuses.last.controller!.requestPage(3);
      await _show(tester, reader, scheduler: scheduler);
      held = false;
      gate.complete();
      await tester.pumpAndSettle();
      expect(reader.positions.last.pageIndex, 3);
      expect(reader.seekResults, hasLength(1));
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'owner replacement suppresses obsolete seek callbacks and late preparation',
    (tester) async {
      final old = _Reader();
      var held = false;
      final gate = Completer<void>();
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await gate.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      await _show(tester, old, scheduler: scheduler);
      await tester.pumpAndSettle();
      held = true;
      final seek = NovelReaderPageSeekRequest(
        requestId: 1,
        episodeId: old.episodeId,
        paginationKey: old.positions.last.paginationKey,
        pageIndex: 7,
      );
      await _show(tester, old, scheduler: scheduler, seek: seek);
      await tester.pumpAndSettle();
      final next = _Reader(episodeId: 'next');
      await _show(tester, next);
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(old.seekResults, isEmpty);
      expect(next.seekResults, isEmpty);
      expect(old.positions, hasLength(1));
      expect(next.positions, hasLength(1));
      expect(old.owner.activeCacheHandles, 0);
      await _unmount(tester, next);
    },
  );

  testWidgets(
    'declarative page seek reuses the active layout and completes only after actual arrival',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final count = reader.positions.length;
      final request = NovelReaderPageSeekRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        paginationKey: reader.positions.last.paginationKey,
        pageIndex: 7,
      );
      await _show(tester, reader, seek: request);
      expect(reader.positions, hasLength(count));
      expect(reader.seekResults, isEmpty);
      await tester.pumpAndSettle();
      expect(reader.positions.last.pageIndex, 7);
      expect(reader.positions.last.hasUserNavigated, isTrue);
      expect(reader.seekResults, [
        (request, NovelReaderPageSeekOutcome.arrived),
      ]);
      expect(reader.statuses.last.controller, same(controller));
      expect(reader.service.calls, 1);
      await _show(
        tester,
        reader,
        seek: NovelReaderPageSeekRequest(
          requestId: 1,
          episodeId: request.episodeId,
          paginationKey: request.paginationKey,
          pageIndex: 7,
        ),
      );
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(count + 1));
      expect(reader.seekResults, hasLength(1));
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'stale or out-of-range seeks report unavailable once without changing the visible position',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final before = reader.positions.last;
      final requests = [
        NovelReaderPageSeekRequest(
          requestId: 1,
          episodeId: 'other',
          paginationKey: before.paginationKey,
          pageIndex: 1,
        ),
        NovelReaderPageSeekRequest(
          requestId: 2,
          episodeId: reader.episodeId,
          paginationKey: 'old-key',
          pageIndex: 1,
        ),
        NovelReaderPageSeekRequest(
          requestId: 3,
          episodeId: reader.episodeId,
          paginationKey: before.paginationKey,
          pageIndex: -1,
        ),
        NovelReaderPageSeekRequest(
          requestId: 4,
          episodeId: reader.episodeId,
          paginationKey: before.paginationKey,
          pageIndex: 10,
        ),
      ];
      for (final request in requests) {
        await _show(tester, reader, seek: request);
        await tester.pumpAndSettle();
        await _show(tester, reader, seek: request);
        await tester.pumpAndSettle();
      }
      expect(reader.positions, [before]);
      expect(reader.seekResults, [
        for (final request in requests)
          (request, NovelReaderPageSeekOutcome.unavailable),
      ]);
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.reading);
      await _unmount(tester, reader);
    },
  );

  for (final replacement in ['seek', 'remove', 'hide', 'other-navigation']) {
    testWidgets(
      '$replacement retires a pending page seek and rejects its late completion',
      (tester) async {
        final reader = _Reader();
        var held = false;
        final gate = Completer<void>();
        final scheduler = NovelReaderNativeWorkScheduler(
          nextFrame: () async {
            if (held) {
              await gate.future;
            } else {
              await WidgetsBinding.instance.endOfFrame;
            }
          },
        );
        await _show(tester, reader, scheduler: scheduler);
        await tester.pumpAndSettle();
        final before = reader.positions.last;
        final first = NovelReaderPageSeekRequest(
          requestId: 1,
          episodeId: reader.episodeId,
          paginationKey: before.paginationKey,
          pageIndex: 7,
        );
        final second = NovelReaderPageSeekRequest(
          requestId: 2,
          episodeId: reader.episodeId,
          paginationKey: before.paginationKey,
          pageIndex: 6,
        );
        held = true;
        await _show(tester, reader, scheduler: scheduler, seek: first);
        await tester.pumpAndSettle();
        expect(reader.seekResults, isEmpty);
        switch (replacement) {
          case 'seek':
            await _show(tester, reader, scheduler: scheduler, seek: second);
          case 'remove':
            await _show(tester, reader, scheduler: scheduler);
          case 'hide':
            await _show(
              tester,
              reader,
              scheduler: scheduler,
              seek: first,
              active: false,
            );
          case 'other-navigation':
            reader.statuses.last.controller!.requestPage(5);
        }
        await tester.pumpAndSettle();
        expect(reader.seekResults, [
          (first, NovelReaderPageSeekOutcome.retired),
        ]);
        expect(reader.positions, [before]);
        held = false;
        gate.complete();
        await tester.pumpAndSettle();
        if (replacement == 'seek') {
          expect(reader.positions.last.pageIndex, 6);
          expect(reader.seekResults.last, (
            second,
            NovelReaderPageSeekOutcome.arrived,
          ));
        } else if (replacement == 'other-navigation') {
          expect(reader.positions.last.pageIndex, 5);
          expect(reader.seekResults, hasLength(1));
        } else {
          expect(reader.positions, [before]);
          expect(reader.seekResults, hasLength(1));
        }
        if (replacement == 'hide') {
          await _show(tester, reader, scheduler: scheduler, seek: first);
          await tester.pumpAndSettle();
          expect(reader.positions.last.pageIndex, before.pageIndex);
          expect(reader.positions.last.hasUserNavigated, isFalse);
          expect(reader.seekResults, hasLength(1));
        }
        await _unmount(tester, reader);
      },
    );
  }

  testWidgets(
    'seek deadline releases the UI intent while preserving the readable page and mode',
    (tester) async {
      final reader = _Reader();
      var held = false;
      final gate = Completer<void>();
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await gate.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      const policy = NovelReaderPaginationPerformancePolicy(
        targetPageWait: Duration(seconds: 1),
      );
      await _show(tester, reader, scheduler: scheduler, performance: policy);
      await tester.pumpAndSettle();
      final before = reader.positions.last;
      final seek = NovelReaderPageSeekRequest(
        requestId: 1,
        episodeId: reader.episodeId,
        paginationKey: before.paginationKey,
        pageIndex: 7,
      );
      held = true;
      await _show(
        tester,
        reader,
        scheduler: scheduler,
        performance: policy,
        seek: seek,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(reader.seekResults, [
        (seek, NovelReaderPageSeekOutcome.unavailable),
      ]);
      expect(reader.positions, [before]);
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.paused);
      expect(find.byType(ForumBodyTextPageSurface), findsOneWidget);
      held = false;
      gate.complete();
      await tester.pumpAndSettle();
      expect(reader.positions, [before]);
      expect(reader.seekResults, hasLength(1));
      expect(reader.preferences.flowMode, NovelReaderFlowMode.pagedLtr);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'Host binds existing chrome commands and rejects them during hidden activity',
    (tester) async {
      final reader = _Reader();
      final navigation = NovelReaderPagedNavigationController();
      addTearDown(navigation.dispose);
      await _show(tester, reader, navigation: navigation);
      await tester.pumpAndSettle();
      final page = reader.positions.last.pageIndex;
      expect(navigation.turnNext(), isTrue);
      await tester.pumpAndSettle();
      expect(reader.positions.last.pageIndex, page + 1);
      await _show(tester, reader, active: false, navigation: navigation);
      await tester.pumpAndSettle();
      final count = reader.positions.length;
      expect(navigation.turnNext(), isFalse);
      expect(navigation.confirmChapterEndNavigation(), isFalse);
      await _show(tester, reader, navigation: navigation);
      await tester.pumpAndSettle();
      expect(reader.positions.length, count + 1);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(navigation.turnPrevious(), isTrue);
      await tester.pumpAndSettle();
      expect(reader.positions.last.pageIndex, page);
      await _unmount(tester, reader);
      expect(navigation.turnNext(), isFalse);
    },
  );

  testWidgets(
    'hiding during a drag returns to the actual confirmed page without navigation',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final before = reader.positions.last;
      final controller = reader.statuses.last.controller;
      final drag = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await drag.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 10));
      await _show(tester, reader, active: false);
      await drag.up();
      await tester.pumpAndSettle();
      expect(reader.positions.last, same(before));
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(reader.positions.last.anchor.textOffset, before.anchor.textOffset);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(reader.activity.last, isFalse);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'owner retirement while hidden closes resources without passive writes on return',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final count = reader.positions.length;
      await _show(tester, reader, active: false);
      await tester.pumpAndSettle();
      reader.owner.dispose();
      await tester.pumpAndSettle();
      expect(reader.owner.activeCacheHandles, 0);
      expect(find.byType(ForumBodyTextPageSurface), findsNothing);
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.closed);
      expect(reader.positions, hasLength(count));
      await _unmount(tester, reader);
    },
  );

  testWidgets('inactive initial Host waits for visibility before preparing', (
    tester,
  ) async {
    final reader = _Reader();
    await _show(tester, reader, active: false);
    await tester.pump(const Duration(seconds: 10));
    expect(reader.service.calls, 0);
    expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.inactive);
    expect(reader.positions, isEmpty);
    expect(reader.owner.activeCacheHandles, 0);
    await _show(tester, reader);
    await tester.pumpAndSettle();
    expect(reader.positions, hasLength(1));
    await _unmount(tester, reader);
  });

  testWidgets(
    'visibility resumes the mounted page with a new reading delivery',
    (tester) async {
      final reader = _Reader();
      final selections = <NovelReaderNativeTextSelection>[];
      await _show(tester, reader, onTextSelection: selections.add);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      controller.requestPage(3);
      await tester.pumpAndSettle();
      final actual = reader.positions.last;
      final prefix = controller.snapshot;
      final previousView = controller.visibleView!;
      final previousDelivery = controller.visibleDelivery!;
      final surface = tester.renderObject(
        find.byType(ForumBodyTextPageSurface),
      );
      await tester.longPressAt(
        tester.getTopLeft(find.byType(ForumBodyTextPageSurface)) +
            const Offset(5, 5),
      );
      final selection = selections.single;
      expect(selection.isCurrent, isTrue);
      final handle = reader.owner.acquireCache();
      final builds = handle.cache.layoutBuildCount;
      await _show(tester, reader, active: false);
      await tester.pumpAndSettle();
      expect(controller.isSuspended, isTrue);
      expect(controller.isClosed, isFalse);
      expect(controller.requestPage(8), isFalse);
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.inactive);
      expect(reader.statuses.last.controller, isNull);
      expect(
        tester.renderObject(find.byType(ForumBodyTextPageSurface)),
        same(surface),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(reader.positions.last, same(actual));
      expect(selection.isCurrent, isTrue);
      await _show(tester, reader);
      final resumed = controller.visibleDelivery!;
      expect(resumed, isNot(same(previousDelivery)));
      expect(resumed.requestId, greaterThan(previousDelivery.requestId));
      expect(resumed.reusesTextMount, isTrue);
      expect(resumed.view, same(previousView));
      expect(selection.isCurrent, isFalse);
      expect(
        tester.renderObject(find.byType(ForumBodyTextPageSurface)),
        same(surface),
      );
      expect(controller.hasPendingNavigation, isFalse);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(controller.snapshot, same(prefix));
      expect(reader.positions.last.anchor.textOffset, actual.anchor.textOffset);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(handle.cache.layoutBuildCount, builds);
      expect(reader.service.calls, 1);
      handle.release();
      await _unmount(tester, reader);
    },
  );

  testWidgets('hiding retires a gated pending seek and its target deadline', (
    tester,
  ) async {
    final reader = _Reader();
    var held = false;
    final released = Completer<void>();
    final scheduler = NovelReaderNativeWorkScheduler(
      nextFrame: () async {
        if (held) {
          await released.future;
        } else {
          await WidgetsBinding.instance.endOfFrame;
        }
      },
    );
    const performance = NovelReaderPaginationPerformancePolicy();
    await _show(tester, reader, scheduler: scheduler, performance: performance);
    await tester.pumpAndSettle();
    final controller = reader.statuses.last.controller!;
    final before = reader.positions.last;
    held = true;
    expect(controller.requestPage(8), isTrue);
    await tester.pump();
    await _show(
      tester,
      reader,
      active: false,
      scheduler: scheduler,
      performance: performance,
    );
    await tester.pump(const Duration(seconds: 20));
    expect(controller.error, isNull);
    expect(controller.readyTarget, isNull);
    expect(reader.positions.last, same(before));
    held = false;
    released.complete();
    await tester.pumpAndSettle();
    expect(reader.positions.last, same(before));
    await _show(tester, reader, scheduler: scheduler, performance: performance);
    await tester.pumpAndSettle();
    expect(reader.statuses.last.controller, same(controller));
    expect(reader.positions.last.pageIndex, before.pageIndex);
    expect(reader.positions.last.hasUserNavigated, isFalse);
    await _unmount(tester, reader);
  });

  testWidgets('late source preparation while hidden cannot mount or publish', (
    tester,
  ) async {
    final reader = _Reader();
    reader.service.gate = Completer<void>();
    await _show(tester, reader);
    await tester.pumpAndSettle();
    expect(reader.service.calls, 1);
    await _show(tester, reader, active: false);
    reader.service.gate!.complete();
    await tester.pumpAndSettle();
    expect(reader.positions, isEmpty);
    expect(find.byType(ForumBodyTextPageSurface), findsNothing);
    expect(reader.owner.activeCacheHandles, 0);
    await _show(tester, reader);
    await tester.pumpAndSettle();
    expect(reader.positions, hasLength(1));
    expect(reader.service.calls, 1);
    await _unmount(tester, reader);
  });

  testWidgets(
    'hidden font changes defer new layout and retire old paint after resume',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final point = reader.positions.last;
      final handle = reader.owner.acquireCache();
      final cache = handle.cache;
      handle.release();
      await _show(tester, reader, active: false);
      await tester.pumpAndSettle();
      reader.fonts.notifyListeners();
      await tester.pumpAndSettle();
      expect(cache.isClosed, isFalse);
      expect(reader.positions.last, same(point));
      expect(reader.owner.activeCacheHandles, 1);
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, isNot(same(controller)));
      expect(reader.positions.last.paginationKey, isNot(point.paginationKey));
      expect(reader.positions.last.anchor.textOffset, point.anchor.textOffset);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(cache.isClosed, isTrue);
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'future-format restore remains readonly after hiding and resuming',
    (tester) async {
      final reader = _Reader();
      final future = reader.snapshot.copyWith(anchorFormatVersion: 37);
      await _show(tester, reader, snapshot: future);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller;
      await _show(tester, reader, snapshot: future, active: false);
      await tester.pumpAndSettle();
      await _show(tester, reader, snapshot: future);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(reader.positions.last.isReadOnlyCompatibilityRestore, isTrue);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      reader.statuses.last.controller!.requestPage(1);
      await tester.pumpAndSettle();
      expect(reader.positions.last.isReadOnlyCompatibilityRestore, isFalse);
      expect(reader.positions.last.hasUserNavigated, isTrue);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'resuming a failed source preserves its error and readable prefix until explicit retry',
    (tester) async {
      final reader = _Reader(
        html:
            '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p><div style="position:absolute">unsupported</div>',
      );
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      final error = controller.error;
      final prefix = controller.snapshot;
      final point = reader.positions.last;
      await _show(tester, reader, active: false);
      await tester.pumpAndSettle();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(controller.error, same(error));
      expect(controller.snapshot, same(prefix));
      expect(reader.positions.last, same(point));
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.paused);
      expect(controller.requestPage(1), isTrue);
      await tester.pumpAndSettle();
      expect(reader.positions.last.pageIndex, 1);
      expect(reader.positions.last.hasUserNavigated, isTrue);
      expect(controller.error, same(error));
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'real Host reuses prepared source/cache and reports EOF only as metrics',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(1));
      expect(reader.positions.single.hasUserNavigated, isFalse);
      expect(reader.statuses.last.isPageCountFinal, isTrue);
      expect(reader.statuses.last.pageCount, 10);
      expect(reader.ready, 1);
      expect(reader.service.calls, 1);
      final handle = reader.owner.acquireCache();
      expect(handle.cache.layoutBuildCount, 1);
      expect(reader.statuses.last.controller!.requestPage(3), isTrue);
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(2));
      expect(reader.positions.last.pageIndex, 3);
      expect(reader.positions.last.hasUserNavigated, isTrue);
      expect(handle.cache.layoutBuildCount, 1);
      handle.release();
      await _unmount(tester, reader);
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(reader.service.calls, 1);
      final warm = reader.owner.acquireCache();
      expect(warm.cache.layoutBuildCount, 1);
      warm.release();
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'font-size reflow keeps the latest canonical visible point rather than stale storage',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-80, 0));
      await tester.pumpAndSettle();
      final before = reader.positions.last;
      expect(reader.activity, contains(true));
      expect(reader.activity.last, isFalse);
      await _show(
        tester,
        reader,
        preferences: reader.preferences.copyWith(fontSize: 20),
      );
      await tester.pumpAndSettle();
      final after = reader.positions.last;
      expect(after.anchor.nodeId, before.anchor.nodeId);
      expect(after.anchor.textOffset, before.anchor.textOffset);
      expect(after.pageIndex, isNot(before.pageIndex));
      expect(after.hasUserNavigated, isFalse);
      expect(reader.service.calls, 1);
      expect(reader.owner.activeCacheHandles, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'future-format compatibility remains readonly through reflow until real navigation',
    (tester) async {
      final reader = _Reader();
      final future = reader.snapshot.copyWith(anchorFormatVersion: 37);
      await _show(tester, reader, snapshot: future);
      await tester.pumpAndSettle();
      expect(reader.positions.last.isReadOnlyCompatibilityRestore, isTrue);
      await _show(
        tester,
        reader,
        snapshot: future,
        preferences: reader.preferences.copyWith(fontSize: 20),
      );
      await tester.pumpAndSettle();
      expect(reader.positions.last.isReadOnlyCompatibilityRestore, isTrue);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      reader.statuses.last.controller!.requestPage(1);
      await tester.pumpAndSettle();
      expect(reader.positions.last.isReadOnlyCompatibilityRestore, isFalse);
      expect(reader.positions.last.hasUserNavigated, isTrue);
      expect(future.anchorFormatVersion, 37);
      await _unmount(tester, reader);
    },
  );

  testWidgets('authority replacement cannot reuse prior navigation proof', (
    tester,
  ) async {
    final reader = _Reader();
    await _show(tester, reader);
    await tester.pumpAndSettle();
    final previous = reader.statuses.last.controller!;
    previous.requestPage(3);
    await tester.pumpAndSettle();
    await _show(
      tester,
      reader,
      authority: Object(),
      snapshot: reader.snapshot.copyWith(anchorFormatVersion: 37),
    );
    await tester.pumpAndSettle();
    expect(previous.isClosed, isTrue);
    expect(reader.positions.last.hasUserNavigated, isFalse);
    expect(reader.positions.last.isReadOnlyCompatibilityRestore, isTrue);
    expect(reader.statuses.last.controller, isNot(same(previous)));
    expect(reader.service.calls, 1);
    await _unmount(tester, reader);
  });

  testWidgets(
    'font notification replaces native cache after visible handoff without reparsing source',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final handle = reader.owner.acquireCache();
      final cache = handle.cache;
      handle.release();
      final before = reader.positions.last;
      reader.fonts.notifyListeners();
      expect(cache.isClosed, isFalse);
      await tester.pumpAndSettle();
      expect(reader.positions.last.paginationKey, isNot(before.paginationKey));
      expect(reader.positions.last.anchor.textOffset, before.anchor.textOffset);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(cache.isClosed, isTrue);
      expect(reader.owner.retainedCacheGenerations, 1);
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'new owner immediately removes old paint and rejects a late old preparation',
    (tester) async {
      final old = _Reader();
      await _show(tester, old);
      await tester.pumpAndSettle();
      final next = _Reader(episodeId: 'new-episode');
      next.service.gate = Completer<void>();
      await _show(tester, next);
      await tester.pumpAndSettle();
      expect(find.byType(ForumBodyTextPageSurface), findsNothing);
      expect(old.owner.activeCacheHandles, 0);
      expect(next.positions, isEmpty);
      next.service.gate!.complete();
      await tester.pumpAndSettle();
      expect(next.positions.single.episodeId, 'new-episode');
      expect(old.positions, hasLength(1));
      await _unmount(tester, next);
    },
  );

  testWidgets(
    'explicit retry preserves prefix data and creates a fresh controller',
    (tester) async {
      final reader = _Reader(
        html:
            '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p><div style="position:absolute">unsupported</div>',
      );
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.paused);
      final previous = reader.statuses.last.controller!;
      final point = reader.positions.last.anchor;
      await _show(tester, reader, retry: 1);
      await tester.pumpAndSettle();
      expect(previous.isClosed, isTrue);
      expect(reader.statuses.last.controller, isNot(same(previous)));
      expect(reader.positions.last.anchor.textOffset, point.textOffset);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(reader.service.calls, 1);
      expect(reader.owner.activeCacheHandles, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'inherited scale changes create a new exact layout without source conversion',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final before = reader.positions.last;
      await _show(tester, reader, scaler: const TextScaler.linear(1.25));
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(2));
      expect(reader.positions.last.paginationKey, isNot(before.paginationKey));
      expect(reader.positions.last.anchor.textOffset, before.anchor.textOffset);
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'equivalent content inputs reuse a controller while paged direction can change',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller;
      await _show(
        tester,
        reader,
        preferences: reader.preferences.copyWith(
          pagePadding: 19,
          flowMode: NovelReaderFlowMode.pagedRtl,
        ),
      );
      await tester.pumpAndSettle();
      expect(reader.statuses.last.controller, same(controller));
      expect(tester.widget<PageView>(find.byType(PageView)).reverse, isTrue);
      expect(reader.positions, hasLength(1));
      expect(reader.owner.activeCacheHandles, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'a late preparation for the previous owner cannot install its controller',
    (tester) async {
      final old = _Reader();
      old.service.gate = Completer<void>();
      await _show(tester, old);
      await tester.pumpAndSettle();
      final next = _Reader(episodeId: 'next');
      await _show(tester, next);
      await tester.pumpAndSettle();
      final current = next.statuses.last.controller;
      old.service.gate!.complete();
      await tester.pumpAndSettle();
      expect(old.positions, isEmpty);
      expect(next.positions, hasLength(1));
      expect(next.positions.single.episodeId, 'next');
      expect(next.statuses.last.controller, same(current));
      expect(old.owner.activeCacheHandles, 0);
      await _unmount(tester, next);
    },
  );

  testWidgets(
    'a second failed retry retains the actually displayed live anchor',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      reader.statuses.last.controller!.requestPage(3);
      await tester.pumpAndSettle();
      final actual = reader.positions.last;
      await _show(
        tester,
        reader,
        limits: const ForumBodyTextPageSessionLimits(
          maxPages: 1,
          maxFragments: 100000,
          maxParagraphs: 16384,
          maxTextCodeUnits: 1024 * 1024,
          maxRuns: 100000,
          maxIssuedLeases: 512,
        ),
      );
      await tester.pumpAndSettle();
      expect(reader.positions.last, same(actual));
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.paused);
      expect(find.byType(ForumBodyTextPageSurface), findsOneWidget);
      expect(reader.owner.activeCacheHandles, 2);
      await _show(tester, reader, retry: 1);
      await tester.pumpAndSettle();
      expect(reader.positions.last.anchor.textOffset, actual.anchor.textOffset);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(reader.owner.activeCacheHandles, 1);
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'empty source completes without opening a native session or inventing a position',
    (tester) async {
      final reader = _Reader(html: ' \n ', episodeId: 'empty');
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.empty);
      expect(reader.owner.activeCacheHandles, 0);
      expect(reader.positions, isEmpty);
      expect(reader.terminal, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'terminal owner retirement removes the body and cannot publish another position',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final count = reader.positions.length;
      reader.owner.dispose();
      await tester.pumpAndSettle();
      expect(find.byType(ForumBodyTextPageSurface), findsNothing);
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.closed);
      expect(reader.positions, hasLength(count));
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'reflow during a drag retires its movement without inventing a navigation',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final before = reader.positions.last;
      final drag = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await drag.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 10));
      await _show(
        tester,
        reader,
        preferences: reader.preferences.copyWith(fontSize: 20),
      );
      await tester.pumpAndSettle();
      await drag.up();
      await tester.pumpAndSettle();
      expect(reader.positions.last.anchor.textOffset, before.anchor.textOffset);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(reader.owner.activeCacheHandles, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'pending theme replacement keeps the actual old canvas with its glyphs',
    (tester) async {
      final reader = _Reader();
      var held = false;
      final released = Completer<void>();
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) {
            await released.future;
          } else {
            await WidgetsBinding.instance.endOfFrame;
          }
        },
      );
      await _show(tester, reader, scheduler: scheduler);
      await tester.pumpAndSettle();
      final background = tester
          .widget<ColoredBox>(find.byType(ColoredBox))
          .color;
      held = true;
      final dark = ThemeData.dark();
      await _show(tester, reader, theme: dark, scheduler: scheduler);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox)).color,
        background,
      );
      expect(reader.positions, hasLength(1));
      held = false;
      released.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox)).color,
        dark.scaffoldBackgroundColor,
      );
      expect(reader.positions, hasLength(2));
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets(
    'switching novel identity cannot reuse a borrowed navigation proof',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final previous = reader.statuses.last.controller!;
      previous.requestPage(3);
      await tester.pumpAndSettle();
      await _show(
        tester,
        reader,
        snapshot: NovelReaderProgressSnapshot(
          novelId: 'another-novel',
          episodeId: reader.episodeId,
          flowMode: NovelReaderFlowMode.pagedLtr,
          scrollOffset: 0,
          pageIndex: 0,
          anchorNodeId: reader.snapshot.anchorNodeId,
          anchorFormatVersion: 37,
          anchorTextIdentity: reader.snapshot.anchorTextIdentity,
          progressPercent: .5,
          isProgressPercentValid: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(previous.isClosed, isTrue);
      expect(reader.positions.last.isReadOnlyCompatibilityRestore, isTrue);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(reader.service.calls, 1);
      await _unmount(tester, reader);
    },
  );

  testWidgets('an empty outcome cannot hide a later preparation failure', (
    tester,
  ) async {
    final reader = _Reader(html: '', episodeId: 'empty');
    await _show(tester, reader);
    await tester.pumpAndSettle();
    expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.empty);
    const html = '<p>Replacement source</p>';
    final semantic =
        const DiscuzNovelReaderDocumentParser(captureSourceProvenance: true)
            .parse(
              episodeId: reader.episodeId,
              rawHtml: '<p>Stale semantic source</p>',
              fallbackParagraphs: const [],
            );
    await _show(tester, reader, rawHtml: html, semantic: semantic);
    await tester.pumpAndSettle();
    expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.failed);
    expect(reader.service.calls, 2);
    expect(reader.positions, isEmpty);
    expect(reader.owner.activeCacheHandles, 0);
    await _unmount(tester, reader);
  });

  testWidgets(
    'invalid geometry never opens a session and recovers when a content box is available',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader, width: 0);
      await tester.pumpAndSettle();
      expect(reader.positions, isEmpty);
      expect(reader.owner.activeCacheHandles, 0);
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.failed);
      await _show(tester, reader);
      await tester.pumpAndSettle();
      expect(reader.positions, hasLength(1));
      expect(reader.ready, 1);
      await _unmount(tester, reader);
    },
  );
}
