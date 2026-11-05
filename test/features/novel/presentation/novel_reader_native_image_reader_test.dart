import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_host_status.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_owner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_layout_host.dart';

import '../test_support/native_reader_image_test_host.dart';

const _html =
    '<img src="https://bbs.yamibo.com/data/attachment/forum/a.png">'
    '<img src="https://bbs.yamibo.com/data/attachment/forum/a.png">';
Future<void> _idle() async {}

final class _Build implements NovelReaderNativeChapterBuildExecutor {
  int calls = 0;
  @override
  Future<NovelReaderNativeChapterPreparation> build(
    NovelReaderNativeChapterBuildRequest request,
  ) {
    calls++;
    return const AdaptiveNovelReaderNativeChapterBuildExecutor().build(request);
  }
}

final class _Reader {
  _Reader({this.html = _html}) {
    semantic = const DiscuzNovelReaderDocumentParser(
      captureSourceProvenance: true,
    ).parse(episodeId: 'episode', rawHtml: html, fallbackParagraphs: const []);
    addTearDown(() {
      owner.dispose();
      fonts.dispose();
      host.completeDimensions();
    });
  }
  late NovelReaderDocument semantic;
  String html;
  void replaceHtml(String value) {
    html = value;
    semantic = const DiscuzNovelReaderDocumentParser(
      captureSourceProvenance: true,
    ).parse(episodeId: 'episode', rawHtml: html, fallbackParagraphs: const []);
  }

  final fonts = ChangeNotifier();
  late final owner = NovelReaderNativeOwner(fontChanges: fonts);
  final authority = Object();
  NativeReaderImageTestHost host = NativeReaderImageTestHost();
  final policy = NativeReaderImageTestHost();
  final positions = <NovelReaderPaginationPosition>[];
  final statuses = <NovelReaderNativeHostStatus>[];
  final build = _Build();
  late final preparation = DefaultNovelReaderNativePreparationService(
    executor: build,
  );
  var preferences = NovelReaderPreferences.defaults().copyWith(
    fontSize: 10,
    lineHeight: 1,
    paragraphSpacing: 0,
  );
  var snapshot = const NovelReaderProgressSnapshot(
    novelId: 'novel',
    episodeId: 'episode',
    flowMode: NovelReaderFlowMode.pagedLtr,
    scrollOffset: 0,
    pageIndex: 0,
    progressPercent: 0,
    isProgressPercentValid: true,
  );
  NovelReaderNativeWorkScheduler scheduler =
      const NovelReaderNativeWorkScheduler();
  NovelReaderNativePagedController get controller => statuses.last.controller!;
  Widget widget({bool beginning = true, bool active = true}) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 100,
        height: 100,
        child: NovelReaderNativeLayoutHost(
          key: const ValueKey('image-reader'),
          owner: owner,
          sourceId: 'episode',
          rawHtml: html,
          semanticDocument: semantic,
          preferences: preferences,
          resolvedFont: ResolvedFont.system,
          progressSnapshot: snapshot,
          readingAuthorityIdentity: authority,
          preparationService: preparation,
          imageHost: host,
          imagePolicy: policy,
          imageThreadId: '521519',
          imageCacheOwnerId: '521519',
          startsAtBeginning: beginning,
          active: active,
          scheduler: scheduler,
          idleScheduler: _idle,
          performance: const NovelReaderPaginationPerformancePolicy(
            enforceBudgets: false,
          ),
          onPositionChanged: positions.add,
          onStatusChanged: statuses.add,
        ),
      ),
    ),
  );
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (done()) return;
  }
  fail('Native image Reader did not reach the expected state');
}

void main() {
  testWidgets(
    'new source at the same image path cannot inherit old resolved geometry',
    (tester) async {
      final reader = _Reader();
      await tester.pumpWidget(reader.widget());
      await _until(tester, () => reader.positions.isNotEmpty);
      final first = reader.controller;
      reader.host.callback(0).resolved?.call(const Size(400, 100));
      await _until(
        tester,
        () =>
            reader.statuses.last.controller != null &&
            !identical(reader.controller, first) &&
            reader.controller.visiblePageIndex != null,
      );
      expect(
        reader.controller.visibleView!.coverage.images.single.rect.height,
        25,
      );
      final old = reader.controller, retired = reader.host.callback(0);
      final oldIdentity = old.snapshot!.identity;
      reader.replaceHtml(reader.html.replaceAll('/a.png', '/b.png'));
      await tester.pumpWidget(reader.widget());
      await _until(
        tester,
        () =>
            reader.statuses.last.controller != null &&
            !identical(reader.controller, old) &&
            reader.controller.visiblePageIndex != null,
      );
      expect(reader.controller.snapshot!.identity, isNot(oldIdentity));
      expect(
        reader.controller.visibleView!.coverage.images.single.rect.height,
        100,
      );
      final current = reader.controller;
      retired.resolved?.call(const Size(999, 1));
      await tester.pumpAndSettle();
      expect(reader.controller, same(current));
      expect(reader.build.calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(reader.owner.activeCacheHandles, 0);
    },
  );

  testWidgets(
    'accepted decoded dimensions create a new layout and restore the actual image slot without reparsing',
    (tester) async {
      final reader = _Reader(html: '<p>A</p>$_html');
      await tester.pumpWidget(reader.widget());
      await _until(tester, () => reader.positions.isNotEmpty);
      expect(reader.controller.requestPage(1), isTrue);
      await _until(tester, () => reader.controller.visiblePageIndex == 1);
      final old = reader.controller;
      final oldSnapshot = old.snapshot!;
      final anchor = reader.positions.last.anchor;
      final fonts = reader.owner.fontGeneration;
      final sourceCacheBytes =
          reader.owner.preparationCache.estimatedRetainedBytes;
      final retired = reader.host.callback(0);
      retired.resolved?.call(const Size(400, 100));
      // The published old rectangle remains immutable before replacement.
      expect(oldSnapshot[1].fragments.single.imageFrame!.height, 100);
      await _until(
        tester,
        () =>
            reader.statuses.last.controller != null &&
            !identical(reader.controller, old) &&
            reader.controller.visiblePageIndex != null,
      );
      final next = reader.controller;
      expect(next.paginationKey, isNot(old.paginationKey));
      expect(next.snapshot!.identity, oldSnapshot.identity);
      expect(reader.positions.last.anchor.nodeId, anchor.nodeId);
      expect(reader.positions.last.anchor.textIdentity, anchor.textIdentity);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(reader.positions.last.pageIndex, 0);
      expect(next.visibleView!.coverage.images.single.rect.height, 25);
      expect(next.visibleView!.coverage.points, isNotEmpty);
      expect(oldSnapshot[1].fragments.single.imageFrame!.height, 100);
      expect(reader.owner.fontGeneration, fonts);
      expect(reader.build.calls, 1);
      expect(
        reader.owner.preparationCache.estimatedRetainedBytes,
        sourceCacheBytes,
      );
      final stable = next;
      reader.host.callback(0).resolved?.call(const Size(800, 200));
      retired.resolved?.call(const Size(999, 1));
      await tester.pumpAndSettle();
      expect(reader.controller, same(stable));
      // A newer decoded size still supersedes a previously resolved hint;
      // becoming non-fallback must not freeze all subsequent dimensions.
      reader.host.callback(0).resolved?.call(const Size(800, 400));
      await _until(
        tester,
        () =>
            reader.statuses.last.controller != null &&
            !identical(reader.controller, stable) &&
            reader.controller.visiblePageIndex != null,
      );
      expect(
        reader.controller.visibleView!.coverage.images.single.rect.height,
        50,
      );
      expect(reader.positions.last.anchor.nodeId, anchor.nodeId);
      expect(reader.build.calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(reader.owner.activeCacheHandles, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cached dimension hints reflow geometry without confirming any image pixels',
    (tester) async {
      final reader = _Reader();
      await tester.pumpWidget(reader.widget());
      await _until(tester, () => reader.positions.isNotEmpty);
      final old = reader.controller;
      reader.host.dimensions.first.complete((
        size: const Size(400, 100),
        layout: const ForumHtmlImageLayout(aspectRatio: 4),
      ));
      await _until(
        tester,
        () =>
            reader.statuses.last.controller != null &&
            !identical(reader.controller, old) &&
            reader.controller.visiblePageIndex != null,
      );
      expect(
        reader.controller.visibleView!.coverage.images.single.rect.height,
        25,
      );
      expect(reader.positions.last.isBodyEndVisible, isFalse);
      expect(reader.positions.last.hasUserNavigated, isFalse);
      expect(reader.build.calls, 1);
      final current = reader.controller;
      reader.host.callback(0).resolved?.call(const Size(double.nan, 10));
      await tester.pumpAndSettle();
      expect(reader.controller, same(current));
      expect(reader.positions.last.isBodyEndVisible, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(reader.owner.activeCacheHandles, 0);
    },
  );

  testWidgets(
    'actual image Reader confirms resource positions separately from decoded dimensions and pixels',
    (tester) async {
      final reader = _Reader();
      await tester.pumpWidget(reader.widget());
      await _until(
        tester,
        () =>
            reader.positions.isNotEmpty &&
            reader.statuses.last.phase == NovelReaderNativeHostPhase.reading,
      );
      expect(reader.statuses.last.phase, NovelReaderNativeHostPhase.reading);
      final initial = reader.positions.last,
          view = reader.controller.visibleView!;
      expect(initial.pageIndex, 0);
      expect(initial.anchor.nodeId, 'node-0');
      expect(initial.anchor.textOffset, 0);
      expect(initial.anchor.textIdentity, startsWith('novel-layout-text-v1:'));
      expect(initial.hasUserNavigated, isTrue);
      expect(initial.isReadOnlyCompatibilityRestore, isFalse);
      expect(initial.isBodyEndVisible, isFalse);
      expect(view.coverage.points, isEmpty);
      expect(view.coverage.images.single.path, '0');
      expect(view.coverage.images.single.sourceRune, isNull);
      expect(view.coverage.images.single.displayUtf16, isNull);
      reader.host.callback(0).resolved?.call(const Size(400, 400));
      await tester.pump();
      expect(reader.positions.last.isBodyEndVisible, isFalse);
      reader.host.callback(0).frame?.call();
      await _until(tester, () => reader.positions.last.isBodyEndVisible);
      expect(reader.positions.last.anchor.nodeId, initial.anchor.nodeId);
      expect(
        reader.positions.last.anchor.textIdentity,
        initial.anchor.textIdentity,
      );
      expect(reader.positions.last.hasUserNavigated, initial.hasUserNavigated);
      expect(reader.positions.last.appliedChapterEntry, isNull);
      reader.host.callback(0).failed?.call();
      await _until(tester, () => !reader.positions.last.isBodyEndVisible);
      expect(reader.controller.requestPage(1), isTrue);
      await _until(tester, () => reader.controller.visiblePageIndex == 1);
      expect(reader.positions.last.anchor.nodeId, 'node-1');
      expect(reader.positions.last.isBodyEndVisible, isFalse);
      reader.host.callback(1).frame?.call();
      await _until(tester, () => reader.positions.last.isBodyEndVisible);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      reader.host.completeDimensions();
      expect(reader.owner.activeCacheHandles, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained image frame can become ready after a failed source is hidden and resumed',
    (tester) async {
      final reader = _Reader(
        html: '$_html<div style="position:absolute">unsupported</div>',
      );
      await tester.pumpWidget(reader.widget());
      await _until(
        tester,
        () => reader.positions.isNotEmpty && reader.controller.error != null,
      );
      final controller = reader.controller;
      final view = controller.visibleView!;
      expect(reader.positions.last.isBodyEndVisible, isFalse);
      await tester.pumpWidget(reader.widget(active: false));
      await tester.pump();
      await tester.pumpWidget(reader.widget());
      await tester.pump();
      expect(reader.controller, same(controller));
      expect(controller.visibleView, same(view));
      expect(controller.error, isNotNull);
      reader.host.callback(0).frame?.call();
      await _until(tester, () => reader.positions.last.isBodyEndVisible);
      expect(reader.positions.last.isPageCountFinal, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(reader.owner.activeCacheHandles, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A to B to A retains source/layout and rejects retired frame callbacks',
    (tester) async {
      final reader = _Reader();
      final a = reader.host, b = NativeReaderImageTestHost();
      addTearDown(b.completeDimensions);
      await tester.pumpWidget(reader.widget());
      await _until(tester, () => reader.positions.isNotEmpty);
      final controller = reader.controller;
      final state = tester.state(find.byType(ForumHtmlImageView).first);
      final retired = a.callback(0);
      reader.host = b;
      await tester.pumpWidget(reader.widget());
      reader.host = a;
      await tester.pumpWidget(reader.widget());
      await tester.pump();
      retired.resolved?.call(const Size(999, 1));
      retired.frame?.call();
      retired.failed?.call();
      await tester.pump();
      expect(a.resolvedSizes, isEmpty);
      expect(b.resolvedSizes, isEmpty);
      expect(reader.positions.last.isBodyEndVisible, isFalse);
      expect(reader.controller, same(controller));
      expect(tester.state(find.byType(ForumHtmlImageView).first), same(state));
      a.callback(0).frame?.call();
      await _until(tester, () => reader.positions.last.isBodyEndVisible);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(reader.owner.activeCacheHandles, 0);
    },
  );

  testWidgets(
    'saved pure-image position restores exactly; future-format recovery stays read-only through pixel readiness',
    (tester) async {
      final reader = _Reader();
      await tester.pumpWidget(reader.widget());
      await _until(tester, () => reader.positions.isNotEmpty);
      expect(reader.controller.requestPage(1), isTrue);
      await _until(tester, () => reader.controller.visiblePageIndex == 1);
      final saved = reader.positions.last;
      for (final version in [1, 37]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        reader.positions.clear();
        reader.snapshot = NovelReaderProgressSnapshot(
          novelId: 'novel',
          episodeId: 'episode',
          flowMode: NovelReaderFlowMode.pagedLtr,
          scrollOffset: 0,
          pageIndex: 99,
          pageCount: 200,
          paginationKey: 'obsolete-layout',
          progressPercent: .8,
          isProgressPercentValid: true,
          anchorNodeId: saved.anchor.nodeId,
          anchorTextOffset: saved.anchor.textOffset,
          anchorFormatVersion: version,
          anchorTextIdentity: saved.anchor.textIdentity,
        );
        await tester.pumpWidget(reader.widget(beginning: false));
        await _until(tester, () => reader.positions.isNotEmpty);
        final restored = reader.positions.last;
        expect(restored.pageIndex, 1);
        expect(restored.anchor.nodeId, saved.anchor.nodeId);
        expect(restored.anchor.textIdentity, saved.anchor.textIdentity);
        expect(restored.hasUserNavigated, isFalse);
        expect(restored.isReadOnlyCompatibilityRestore, version != 1);
        expect(restored.isBodyEndVisible, isFalse);
        reader.host.callback(1).frame?.call();
        await _until(tester, () => reader.positions.last.isBodyEndVisible);
        expect(
          reader.positions.last.isReadOnlyCompatibilityRestore,
          version != 1,
        );
        expect(reader.positions.last.hasUserNavigated, isFalse);
        final beforeReflow = reader.controller;
        reader.host.callback(1).resolved?.call(const Size(400, 100));
        await _until(
          tester,
          () =>
              reader.statuses.last.controller != null &&
              !identical(reader.controller, beforeReflow) &&
              reader.controller.visiblePageIndex != null,
        );
        expect(reader.positions.last.anchor.nodeId, saved.anchor.nodeId);
        expect(
          reader.positions.last.isReadOnlyCompatibilityRestore,
          version != 1,
        );
        expect(reader.positions.last.hasUserNavigated, isFalse);
        expect(reader.controller.requestPage(0), isTrue);
        await _until(tester, () => reader.controller.visiblePageIndex == 0);
        expect(reader.positions.last.hasUserNavigated, isTrue);
        expect(reader.positions.last.isReadOnlyCompatibilityRestore, isFalse);
        expect(reader.positions.last.anchor.nodeId, 'node-0');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(reader.owner.activeCacheHandles, 0);
    },
  );

  testWidgets(
    'automatic dimension reflow keeps zero-native page 45 painted until a replacement mounts',
    (tester) async {
      final reader = _Reader(html: List.filled(65, _html).join());
      var held = false, waits = 0;
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      reader.scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () {
          if (held) {
            waits++;
            return gate.future;
          }
          return Future.value();
        },
      );
      await tester.pumpWidget(reader.widget());
      await _until(tester, () => reader.positions.isNotEmpty);
      expect(reader.controller.requestPage(45), isTrue);
      await _until(tester, () => reader.controller.visiblePageIndex == 45);
      final oldController = reader.controller;
      final oldView = oldController.visibleView!;
      held = true;
      final fonts = reader.owner.fontGeneration;
      reader.host.callback(45).resolved?.call(const Size(400, 100));
      await _until(
        tester,
        () =>
            waits > 0 &&
            reader.statuses.last.phase == NovelReaderNativeHostPhase.preparing,
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('native-test-image-45')),
        findsOneWidget,
      );
      expect(reader.owner.retainedCacheGenerations, inInclusiveRange(1, 2));
      expect(find.byType(ForumHtmlImageView), findsWidgets);
      expect(oldView.coverage.images, isNotEmpty);
      expect(tester.takeException(), isNull);
      gate.complete();
      await _until(
        tester,
        () =>
            reader.statuses.last.controller != null &&
            !identical(reader.controller, oldController) &&
            reader.controller.visiblePageIndex == 45,
      );
      await tester.pump();
      expect(reader.owner.retainedCacheGenerations, 1);
      expect(reader.owner.fontGeneration, fonts);
      expect(reader.build.calls, 1);
      expect(
        reader.controller.visibleView!.coverage.images.single.rect.height,
        25,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(reader.owner.activeCacheHandles, 0);
    },
  );
}
