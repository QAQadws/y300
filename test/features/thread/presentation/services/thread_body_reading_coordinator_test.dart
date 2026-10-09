import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/services/thread_body_reading_coordinator.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('samples the actual HTML body without header and footer', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host());
    await tester.pumpAndSettle();
    final sample = harness.observer.viewports.last.samples.single;
    expect(sample.relativeBodyTop, 140);
    expect(sample.bodyHeight, greaterThan(1000));
    expect(sample.effectiveViewportHeight, 400);
    expect(sample.visibleExtent, 260);
    expect(sample.bodyReady, isTrue);
    expect(sample.finalBoundaryKnown, isTrue);
    expect(harness.observer.viewports.last.userNavigationRevision, 0);
  });

  testWidgets(
    'quick navigation cancels pending completion before its first frame',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host());
      await tester.pumpAndSettle();
      final quick = ThreadDetailQuickScrollCoordinator(
        scrollController: harness.controller,
        onNavigationStarted: harness.coordinator.beginExplicitNavigation,
        onUserNavigation: harness.coordinator.markUserNavigation,
      );
      addTearDown(quick.dispose);
      quick.updateMetrics(harness.controller.position);
      var completed = 0;
      final previousCancellations = harness.observer.completionCancellations;
      harness.observer.completionTimer = Timer(
        const Duration(milliseconds: 1),
        () => completed++,
      );
      final navigation = quick.navigate(animate: true);
      // No pump occurs between the tap and this assertion. The old completion
      // must be cancelled synchronously, before a layout can report idle=false.
      expect(
        harness.observer.completionCancellations,
        previousCancellations + 1,
      );
      expect(harness.observer.viewports.last.userNavigationRevision, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(completed, 0);
      quick.cancelNavigation();
      await tester.pumpAndSettle();
      await navigation;
      expect(harness.observer.viewports.last.userNavigationRevision, 0);
    },
  );

  testWidgets('restores the body fraction once and remains passive', (
    tester,
  ) async {
    final harness = _Harness(fraction: 0.42);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host());
    await tester.pumpAndSettle();
    var viewport = harness.observer.viewports.last;
    var sample = viewport.samples.single;
    expect(
      -sample.relativeBodyTop / (sample.bodyHeight - 400),
      closeTo(0.42, 0.001),
    );
    expect(viewport.restoreSettled, isTrue);
    expect(viewport.userNavigationRevision, 0);
    expect(harness.observer.restoreCalls, 1);
    harness.controller.jumpTo(harness.controller.offset + 120);
    await tester.pumpAndSettle();
    expect(harness.observer.restoreCalls, 1);
    expect(harness.observer.viewports.last.userNavigationRevision, 0);
    await tester.drag(find.byKey(harness.viewportKey), const Offset(0, -100));
    await tester.pumpAndSettle();
    viewport = harness.observer.viewports.last;
    expect(viewport.userNavigationRevision, greaterThan(0));
    expect(viewport.idle, isTrue);
  });

  testWidgets('leaving the body for footer emits no fabricated body position', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host());
    await tester.pumpAndSettle();
    final sample = harness.observer.viewports.last.samples.single;
    harness.controller.jumpTo(140 + sample.bodyHeight + 1);
    await tester.pumpAndSettle();
    expect(harness.observer.viewports.last.samples, isEmpty);
  });

  testWidgets('hidden measurement and retired frame callbacks do not report', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host());
    await tester.pumpAndSettle();
    final previousCount = harness.observer.viewports.length;
    harness.coordinator.setActive(false);
    harness.controller.jumpTo(300);
    harness.coordinator.schedule();
    await tester.pumpAndSettle();
    expect(harness.observer.viewports.length, previousCount);
    harness.coordinator.setActive(true);
    await tester.pumpAndSettle();
    expect(harness.observer.viewports.length, greaterThan(previousCount));
    harness.coordinator.schedule();
    harness.coordinator.dispose();
    final retiredCount = harness.observer.viewports.length;
    await tester.pumpAndSettle();
    expect(harness.observer.viewports.length, retiredCount);
  });

  testWidgets(
    'explicit page navigation cancels initial restore without replaying old navigation',
    (tester) async {
      final harness = _Harness(fraction: 0.6);
      addTearDown(harness.dispose);
      // A page selection can arrive before the initial target HTML finishes.
      harness.coordinator.markUserNavigation();
      await tester.pumpWidget(harness.host());
      await tester.pumpAndSettle();
      expect(harness.observer.restoreCalls, 0);
      expect(harness.observer.viewports.last.restoreSettled, isTrue);
      expect(harness.observer.viewports.last.userNavigationRevision, 1);
      harness.coordinator.bindContent(
        tid: '100',
        page: 2,
        identity: Object(),
        viewportKey: harness.viewportKey,
      );
      await tester.pumpAndSettle();
      expect(harness.observer.viewports.last.page, 2);
      expect(harness.observer.viewports.last.userNavigationRevision, 1);
    },
  );

  testWidgets(
    'landing image first frame rechecks the actual body height before settling',
    (tester) async {
      final viewportKey = GlobalKey();
      final bodyKey = GlobalKey();
      final controller = ScrollController();
      final observer = _Observer(0.5);
      final coordinator = ThreadBodyReadingCoordinator(
        observer: observer,
        scrollController: controller,
        initialTargetPid: '200',
      );
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      var imageReady = true;
      var bodyHeight = 1000.0;
      var firstJump = true;
      controller.addListener(() {
        if (firstJump && controller.offset > 0) {
          firstJump = false;
          imageReady = false;
        }
      });
      coordinator.bindContent(
        tid: '100',
        page: 1,
        identity: observer,
        viewportKey: viewportKey,
      );
      coordinator.register(
        ThreadBodyReadingHandle(
          owner: observer,
          key: bodyKey,
          tid: '100',
          pid: '200',
          bodyIdentity: 'body',
          htmlReady: () => true,
          imagesReady: (_) => imageReady,
          finalBoundaryKnown: () => true,
          layoutRevision: () => bodyHeight,
        ),
      );
      Widget scene() => LocalizedTestApp(
        home: Scaffold(
          body: SizedBox(
            key: viewportKey,
            height: 400,
            width: 400,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                coordinator.handleScroll(notification);
                return false;
              },
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: [
                    const SizedBox(height: 140),
                    ThreadBodyReadingBoundary(
                      key: bodyKey,
                      coordinator: coordinator,
                      child: SizedBox(height: bodyHeight),
                    ),
                    const SizedBox(height: 800),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      expect(observer.viewports.last.restoreSettled, isFalse);
      expect(controller.offset, 440);
      bodyHeight = 1400;
      imageReady = true;
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      expect(controller.offset, 640);
      expect(observer.viewports.last.restoreSettled, isTrue);
      expect(observer.viewports.last.userNavigationRevision, 0);
      expect(observer.restoreCalls, 1);
    },
  );

  testWidgets('folds use current visible geometry without inventing navigation', (
    tester,
  ) async {
    final harness = _Harness(
      html:
          '<p>start</p><div class="showcollapse_box" id="fold"><div class="showcollapse_title">fold</div><div class="showcollapse_content"><p>hidden text</p></div></div>',
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host());
    await tester.pumpAndSettle();
    final closed = harness.observer.viewports.last.samples.single;
    expect(closed.finalBoundaryKnown, isTrue);
    expect(find.text('hidden text', findRichText: true), findsNothing);
    final cancellations = harness.observer.completionCancellations;
    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-200-fold')),
    );
    await tester.pumpAndSettle();
    final expanded = harness.observer.viewports.last.samples.single;
    expect(expanded.finalBoundaryKnown, isTrue);
    expect(expanded.bodyHeight, greaterThan(closed.bodyHeight));
    expect(expanded.geometryIdentity, isNot(closed.geometryIdentity));
    expect(find.text('hidden text', findRichText: true), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-200-fold')),
    );
    await tester.pumpAndSettle();
    final closedAgain = harness.observer.viewports.last.samples.single;
    expect(closedAgain.finalBoundaryKnown, isTrue);
    expect(closedAgain.bodyHeight, closed.bodyHeight);
    expect(closedAgain.geometryIdentity, isNot(expanded.geometryIdentity));
    expect(closedAgain.geometryIdentity, isNot(closed.geometryIdentity));
    expect(harness.observer.viewports.last.userNavigationRevision, 0);
    expect(
      harness.observer.completionCancellations,
      greaterThan(cancellations),
    );
    expect(find.text('hidden text', findRichText: true), findsNothing);
  });

  testWidgets(
    'PID-centered native content restores using actual body coordinates',
    (tester) async {
      final harness = _Harness(fraction: 0.4);
      addTearDown(harness.dispose);
      final state = ThreadDetailPageState.initial(tid: '100', subject: 'title')
          .copyWith(
            currentPage: 2,
            posts: [
              _post('199', '<p>earlier floor</p>', 1),
              _post('200', harness.html, 2),
              _post('201', '<p>ordinary reply</p>', 3),
            ],
            isLoadingInitial: false,
          );
      await tester.pumpWidget(
        ProviderScope(
          child: LocalizedTestApp(
            home: Scaffold(
              body: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  harness.coordinator.handleScroll(notification);
                  return false;
                },
                child: ThreadDetailContent(
                  state: state,
                  scrollController: harness.controller,
                  bodyReadingCoordinator: harness.coordinator,
                  targetPid: '200',
                  imageReferer: '',
                  onLoadPreviousPage: () {},
                  onLoadNextPage: () {},
                  onLoadPageNumber: (_) {},
                  onOpenAuthorProfile: (_) {},
                  onOpenCommentAuthorProfile: (_) {},
                  onCopyActionUrl: (_, _) {},
                  onOpenPostLink: (_) {},
                  onOpenPostActions: (_) {},
                  onTogglePollOption: (_, _) {},
                  onSubmitPollVote: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = harness.observer.viewports.last;
      final sample = viewport.samples.single;
      expect(sample.pid, '200');
      expect(viewport.page, 2);
      expect(
        -sample.relativeBodyTop /
            (sample.bodyHeight - sample.effectiveViewportHeight),
        closeTo(0.4, 0.001),
      );
      expect(viewport.userNavigationRevision, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

ThreadPost _post(String pid, String html, int number) => ThreadPost(
  pid: pid,
  author: 'author',
  authorId: '1',
  message: html,
  number: number,
  isFirst: number == 1,
  dateline: 'date',
);

class _Harness {
  _Harness({double? fraction, String? html})
    : html =
          html ??
          List.filled(
            80,
            '<p>Visible chapter body words used to measure actual HTML.</p>',
          ).join() {
    observer = _Observer(fraction);
    coordinator = ThreadBodyReadingCoordinator(
      observer: observer,
      scrollController: controller,
      initialTargetPid: '200',
    );
  }
  final String html;
  final controller = ScrollController();
  final viewportKey = GlobalKey();
  late final _Observer observer;
  late final ThreadBodyReadingCoordinator coordinator;
  final _contentIdentity = Object();
  Widget host() {
    coordinator.bindContent(
      tid: '100',
      page: 1,
      identity: _contentIdentity,
      viewportKey: viewportKey,
    );
    final theme = ThemeData.light();
    return ProviderScope(
      child: LocalizedTestApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: viewportKey,
              height: 400,
              width: 400,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  coordinator.handleScroll(notification);
                  return false;
                },
                child: SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    children: [
                      const SizedBox(height: 140),
                      ThreadPostHtmlFirstBody(
                        post: _post('200', html, 1),
                        threadId: '100',
                        imageReferer: '',
                        onOpenPostLink: (_) {},
                        onOpenPostImage: null,
                        readingCoordinator: coordinator,
                        theme: const ForumHtmlRenderThemeFactory()
                            .fromMaterialTheme(
                              theme: theme,
                              surface: theme.colorScheme.surface,
                            ),
                      ),
                      const SizedBox(height: 800),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void dispose() {
    coordinator.dispose();
    controller.dispose();
  }
}

class _Observer implements ThreadBodyReadingObserver {
  _Observer(this.fraction);
  final double? fraction;
  final viewports = <ThreadBodyReadingViewport>[];
  final identities = <Object>[];
  int restoreCalls = 0;
  int completionCancellations = 0;
  Timer? completionTimer;
  @override
  bool tracks(String tid, String pid) => tid == '100' && pid == '200';
  @override
  ThreadBodyRestoreTarget? restoreTarget({
    required String tid,
    required String pid,
    required Object bodyIdentity,
  }) {
    restoreCalls++;
    return fraction == null
        ? null
        : ThreadBodyRestoreTarget(fraction: fraction!, requestIdentity: this);
  }

  @override
  void onContentChanged(Object contentIdentity) =>
      identities.add(contentIdentity);
  @override
  void onViewport(ThreadBodyReadingViewport viewport) =>
      viewports.add(viewport);
  @override
  void onVisibility({required bool frontmost, required bool resumed}) {}
  @override
  void cancelPendingCompletion() {
    completionCancellations++;
    completionTimer?.cancel();
    completionTimer = null;
  }

  @override
  Future<void> flush() async {}
  @override
  void retire() {}
}
