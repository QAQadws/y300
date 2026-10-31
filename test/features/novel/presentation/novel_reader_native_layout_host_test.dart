import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:y300/features/novel/presentation/controllers/novel_reader_paged_navigation_controller.dart';
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
  final seekResults =
      <(NovelReaderPageSeekRequest, NovelReaderPageSeekOutcome)>[];
  final anchorResults =
      <(NovelReaderAnchorNavigationRequest, NovelReaderNavigationOutcome)>[];
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
  NovelReaderPagedNavigationController? navigation,
  NovelReaderPageSeekRequest? seek,
  NovelReaderAnchorNavigationRequest? anchorNavigation,
  bool startsAtBeginning = false,
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
                navigationController: navigation,
                pageSeekRequest: seek,
                navigationRequest: anchorNavigation,
                startsAtBeginning: startsAtBeginning,
                onNavigationFinished: (request, outcome) =>
                    reader.anchorResults.add((request, outcome)),
                onPageSeekFinished: (request, outcome) =>
                    reader.seekResults.add((request, outcome)),
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
            '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p><blockquote>unsupported</blockquote><p>outside</p>',
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
            '<p>${List.filled(20, 'abcdefghijklmnopqrst').join()}</p><blockquote>unsupported</blockquote>',
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
