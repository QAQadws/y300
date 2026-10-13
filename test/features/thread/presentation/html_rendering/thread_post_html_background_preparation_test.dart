import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/services/thread_body_reading_coordinator.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets(
    'new preparation retires old readiness and reading geometry immediately',
    (tester) async {
      final worker = _Worker();
      final executor = _executor(worker);
      final harness = _Harness();
      await tester.pumpWidget(
        harness.host('<p>First body</p>', executor: executor),
      );
      await _frames(tester);
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
      expect(harness.observer.viewports.last.samples, isEmpty);
      worker.complete(0);
      await _frames(tester);
      final oldSample = harness.observer.viewports.last.samples.single;
      expect(oldSample.bodyReady, isTrue);
      final oldReady = tester
          .widget<ForumHtmlWidgetPostRenderer>(
            find.byType(ForumHtmlWidgetPostRenderer),
          )
          .onBodyBuilt!;

      final firstPendingViewport = harness.observer.viewports.length;
      await tester.pumpWidget(
        harness.host('<p>Retired next body</p>', executor: executor),
      );
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
      expect(find.text('First body', findRichText: true), findsNothing);
      oldReady();
      harness.coordinator.schedule();
      await _frames(tester);
      expect(
        harness.observer.viewports
            .skip(firstPendingViewport)
            .every((viewport) => viewport.samples.isEmpty),
        isTrue,
      );

      await tester.pumpWidget(
        harness.host('<p>Current body</p>', executor: executor),
      );
      worker.complete(1);
      await _frames(tester);
      oldReady();
      harness.coordinator.schedule();
      await _frames(tester);
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
      expect(harness.observer.viewports.last.samples, isEmpty);
      worker.complete(2);
      await _frames(tester);
      final currentSample = harness.observer.viewports.last.samples.single;
      expect(currentSample.bodyReady, isTrue);
      expect(currentSample.bodyIdentity, isNot(oldSample.bodyIdentity));
      expect(find.text('Current body', findRichText: true), findsOneWidget);
      expect(find.text('Retired next body', findRichText: true), findsNothing);
      expect(harness.observer.restoreCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'thread theme and owner changes ignore earlier prepared results',
    (tester) async {
      final worker = _Worker();
      final executor = _executor(worker);
      final harness = _Harness();
      await tester.pumpWidget(
        harness.host('<p>Shared body</p>', executor: executor),
      );
      await tester.pumpWidget(
        harness.host(
          '<p>Shared body</p>',
          executor: executor,
          theme: _darkTheme,
        ),
      );
      await tester.pumpWidget(
        harness.host(
          '<p>Shared body</p>',
          executor: executor,
          theme: _darkTheme,
          tid: '101',
        ),
      );
      expect(worker.jobs, hasLength(3));
      worker.complete(1);
      worker.complete(0);
      await _frames(tester);
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
      expect(harness.observer.viewports.last.samples, isEmpty);
      expect(worker.jobs.last.input.threadId, '101');
      expect(worker.jobs.last.input.imageCacheOwnerId, '101');
      worker.complete(2);
      await _frames(tester);
      final sample = harness.observer.viewports.last.samples.single;
      expect(sample.tid, '101');
      expect(sample.bodyReady, isTrue);
      expect(
        tester
            .widget<ForumHtmlRenderer>(find.byType(ForumHtmlRenderer))
            .preparedDocument
            .themeSignature,
        _darkTheme.signature,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('executor replacement retires the already ready thread handle', (
    tester,
  ) async {
    final firstWorker = _Worker();
    final secondWorker = _Worker();
    final firstExecutor = _executor(firstWorker);
    final secondExecutor = _executor(secondWorker);
    final harness = _Harness();
    const html = '<p>Rebound body</p>';
    await tester.pumpWidget(harness.host(html, executor: firstExecutor));
    firstWorker.complete(0);
    await _frames(tester);
    expect(harness.observer.viewports.last.samples.single.bodyReady, isTrue);
    final oldReady = tester
        .widget<ForumHtmlWidgetPostRenderer>(
          find.byType(ForumHtmlWidgetPostRenderer),
        )
        .onBodyBuilt!;
    await tester.pumpWidget(harness.host(html, executor: secondExecutor));
    oldReady();
    harness.coordinator.schedule();
    await _frames(tester);
    expect(harness.observer.viewports.last.samples, isEmpty);
    expect(find.text('Rebound body', findRichText: true), findsNothing);
    expect(secondWorker.jobs, hasLength(1));
    secondWorker.complete(0);
    await _frames(tester);
    expect(harness.observer.viewports.last.samples.single.bodyReady, isTrue);
    expect(find.text('Rebound body', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and disposed thread bodies retire pending preparation', (
    tester,
  ) async {
    final worker = _Worker();
    final executor = _executor(worker);
    final harness = _Harness();
    await tester.pumpWidget(
      harness.host('<p>Retired empty body</p>', executor: executor),
    );
    await tester.pumpWidget(harness.host('', executor: executor));
    expect(find.byType(ForumHtmlPreparationPlaceholder), findsNothing);
    expect(find.text('Empty body fallback'), findsOneWidget);
    worker.complete(0);
    await _frames(tester);
    expect(find.byType(ForumHtmlRenderer), findsNothing);
    expect(harness.observer.viewports.last.samples, isEmpty);

    await tester.pumpWidget(
      harness.host('<p>Disposed body</p>', executor: executor),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    final reportedBeforeCompletion = harness.observer.viewports.length;
    worker.complete(1);
    await _frames(tester);
    expect(harness.observer.viewports, hasLength(reportedBeforeCompletion));
    expect(find.text('Disposed body', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom thread preparation remains synchronous', (tester) async {
    final worker = _Worker();
    final executor = _executor(worker);
    final harness = _Harness();
    final preparer = _CustomPreparer();
    await tester.pumpWidget(
      harness.host(
        '<p>Custom body</p>',
        executor: executor,
        preparer: preparer,
      ),
    );
    await _frames(tester);
    expect(worker.jobs, isEmpty);
    expect(preparer.calls, 1);
    expect(find.byType(ForumHtmlPreparationPlaceholder), findsNothing);
    expect(harness.observer.viewports.last.samples.single.bodyReady, isTrue);
    expect(find.text('Custom body', findRichText: true), findsOneWidget);
  });
}

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.pump();
  }
}

ForumHtmlPreparationExecutor _executor(_Worker worker) {
  final executor = ForumHtmlPreparationExecutor(
    codeUnitThreshold: 0,
    maxConcurrent: 4,
    worker: worker.call,
  );
  addTearDown(executor.dispose);
  return executor;
}

final class _Worker {
  final jobs =
      <
        ({
          ForumHtmlBackgroundPreparationInput input,
          Completer<ForumHtmlPreparedRenderDocument> result,
        })
      >[];

  Future<ForumHtmlPreparedRenderDocument> call(
    ForumHtmlBackgroundPreparationInput input,
  ) {
    final result = Completer<ForumHtmlPreparedRenderDocument>();
    jobs.add((input: input, result: result));
    return result.future;
  }

  void complete(int index) =>
      jobs[index].result.complete(jobs[index].input.prepare());
}

final class _Harness {
  _Harness() {
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
      container.dispose();
    });
  }

  final container = ProviderContainer(
    overrides: [
      forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
        const _Preferences(),
      ),
    ],
  );
  final controller = ScrollController();
  final viewportKey = GlobalKey();
  final observer = _Observer();
  final _contentIdentity = Object();
  late final coordinator = ThreadBodyReadingCoordinator(
    observer: observer,
    scrollController: controller,
    initialTargetPid: null,
  );

  Widget host(
    String html, {
    required ForumHtmlPreparationExecutor executor,
    ForumHtmlThemeContext? theme,
    String tid = '100',
    ForumHtmlRenderPreparer preparer = const DefaultForumHtmlRenderPreparer(),
  }) {
    coordinator.bindContent(
      tid: tid,
      page: 1,
      identity: _contentIdentity,
      viewportKey: viewportKey,
    );
    return UncontrolledProviderScope(
      container: container,
      child: LocalizedTestApp(
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: viewportKey,
              height: 400,
              width: 400,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: [
                    const SizedBox(height: 140),
                    ThreadPostHtmlFirstBody(
                      post: ThreadPost(
                        pid: '200',
                        author: 'author',
                        authorId: '1',
                        message: html,
                        number: 1,
                        isFirst: true,
                        dateline: 'date',
                      ),
                      threadId: tid,
                      imageReferer: '',
                      onOpenPostLink: (_) {},
                      onOpenPostImage: null,
                      theme: theme ?? _lightTheme,
                      readingCoordinator: coordinator,
                      preparationExecutor: executor,
                      renderPreparer: preparer,
                      fallback: const Text('Empty body fallback'),
                    ),
                    const SizedBox(height: 800),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _Observer implements ThreadBodyReadingObserver {
  final viewports = <ThreadBodyReadingViewport>[];
  int restoreCalls = 0;

  @override
  bool tracks(String tid, String pid) => pid == '200';
  @override
  void onContentChanged(Object contentIdentity) {}
  @override
  void onViewport(ThreadBodyReadingViewport viewport) =>
      viewports.add(viewport);
  @override
  ThreadBodyRestoreTarget? restoreTarget({
    required String tid,
    required String pid,
    required Object bodyIdentity,
  }) {
    restoreCalls++;
    return null;
  }

  @override
  void cancelPendingCompletion() {}
  @override
  void onVisibility({required bool frontmost, required bool resumed}) {}
  @override
  Future<void> flush() async {}
  @override
  void retire() {}
}

final class _Preferences implements ForumHtmlReaderPreferencesRepository {
  const _Preferences();
  @override
  Future<ForumHtmlReaderPreferences> load() async =>
      ForumHtmlReaderPreferences.defaults();
  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {}
}

final class _CustomPreparer implements ForumHtmlRenderPreparer {
  int calls = 0;
  @override
  ForumHtmlPreparedRenderDocument prepare({
    required String html,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) {
    calls++;
    return const DefaultForumHtmlRenderPreparer().prepare(
      html: html,
      preferences: preferences,
      theme: theme,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
    );
  }
}

final _lightTheme = const ForumHtmlRenderThemeFactory().fromMaterialTheme(
  theme: ThemeData.light(),
  surface: ThemeData.light().colorScheme.surface,
);
final _darkTheme = const ForumHtmlRenderThemeFactory().fromMaterialTheme(
  theme: ThemeData.dark(),
  surface: ThemeData.dark().colorScheme.surface,
);
