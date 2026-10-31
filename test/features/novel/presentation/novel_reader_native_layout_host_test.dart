import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_host_status.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_owner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_layout_host.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

Future<void> _idle() async {}

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
  _Reader({String? html, this.episodeId = 'episode'}) {
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
  late final String rawHtml;
  late final NovelReaderDocument semantic;
  late NovelReaderProgressSnapshot snapshot;
  final fonts = ChangeNotifier();
  late final owner = NovelReaderNativeOwner(fontChanges: fonts);
  final service = _Preparation();
  final authority = Object();
  final positions = <NovelReaderPaginationPosition>[];
  final statuses = <NovelReaderNativeHostStatus>[];
  final activity = <bool>[];
  int ready = 0;
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
                preparationService: reader.service,
                onPositionChanged: reader.positions.add,
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
  );
}

Future<void> _unmount(WidgetTester tester, _Reader reader) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(reader.owner.activeCacheHandles, 0);
  expect(tester.takeException(), isNull);
}

void main() {
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
    'visibility resumes the same source and canonical point without reshaping',
    (tester) async {
      final reader = _Reader();
      await _show(tester, reader);
      await tester.pumpAndSettle();
      final controller = reader.statuses.last.controller!;
      controller.requestPage(3);
      await tester.pumpAndSettle();
      final actual = reader.positions.last;
      final prefix = controller.snapshot;
      final surface = tester.renderObject(
        find.byType(ForumBodyTextPageSurface),
      );
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
      await _show(tester, reader);
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
            '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p><blockquote>unsupported</blockquote>',
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
            '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p><blockquote>unsupported</blockquote>',
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
    const html = '<p></p>';
    final semantic =
        const DiscuzNovelReaderDocumentParser(captureSourceProvenance: true)
            .parse(
              episodeId: reader.episodeId,
              rawHtml: html,
              fallbackParagraphs: const [],
            );
    await _show(tester, reader, rawHtml: html, semantic: semantic);
    await tester.pumpAndSettle();
    expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.failed);
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
