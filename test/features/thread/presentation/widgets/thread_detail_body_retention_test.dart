import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/services/thread_body_presentation.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';
import 'package:y300/features/thread/presentation/services/thread_body_reading_coordinator.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets(
    'native endpoint prepares an unmounted target before scrolling and transfers its source',
    (tester) async {
      final host = _PageHost(nativeBody: true);
      addTearDown(host.dispose);
      await tester.pumpWidget(host.widget());
      await _until(
        tester,
        () => find.byType(ForumBodyFlowBox).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(_body(tester, 'four'), isNull);
      final preloads = tester
          .widget<ForumNativeBodyFlowPreloadScope>(
            find.byType(ForumNativeBodyFlowPreloadScope),
          )
          .notifier!;
      final request = ForumHtmlPreparationRequest(
        html: host.posts.last.message.trim(),
        preferences: host.container
            .read(forumHtmlReaderFontBindingProvider)
            .preferences,
        theme: _body(tester, 'one')!.theme,
        sourceId: 'four',
        threadId: '100',
        imageCacheOwnerId: '100',
        preparer: const DefaultForumHtmlRenderPreparer(
          enablePlainTextLinks: true,
        ),
      );
      ForumNativeBodyPreparedSource? prepared;
      double? preparationOffset;
      bool? wasMounted;
      void observe() {
        // The controller publishes after all target text/table delivery is ready.
        final candidate = preloads.peek(request.identity);
        if (candidate == null || prepared != null) return;
        prepared = candidate;
        preparationOffset = host.controller.offset;
        wasMounted = find
            .byType(ThreadPostHtmlFirstBody, skipOffstage: false)
            .evaluate()
            .any(
              (element) =>
                  (element.widget as ThreadPostHtmlFirstBody).post.pid ==
                  'four',
            );
      }

      preloads.addListener(observe);
      host.quick.updateMetrics(host.controller.position);
      var finished = false;
      final navigation = host.quick
          .navigate(animate: false)
          .then((_) => finished = true);
      for (
        var frame = 0;
        frame < 200 && prepared == null && !finished;
        frame++
      ) {
        await tester.pump();
      }
      expect(prepared, isNotNull);
      var transferred = false;
      for (var frame = 0; frame < 200 && !finished; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        transferred |= tester
            .widgetList<ForumBodyFlowBox>(find.byType(ForumBodyFlowBox))
            .any((box) => identical(box.session, prepared!.source.session));
      }
      expect(finished, isTrue);
      await navigation;
      preloads.removeListener(observe);
      expect(prepared, isNotNull);
      expect(preparationOffset, 0);
      expect(wasMounted, isFalse);
      await tester.pumpAndSettle();
      expect(transferred, isTrue);
      expect(
        tester
            .widgetList<ForumBodyFlowBox>(find.byType(ForumBodyFlowBox))
            .any((box) => identical(box.session, prepared!.source.session)),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(prepared!.source.isClosed, isTrue);
      expect(prepared!.source.session!.activeIssuedFragments, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native completed height is retained before an immediate remount',
    (tester) async {
      final store = ThreadBodyPresentationStore();
      final container = _container();
      final pending =
          <
            ({
              ForumHtmlBackgroundPreparationInput input,
              Completer<ForumHtmlPreparedRenderDocument> result,
            })
          >[];
      final executor = ForumHtmlPreparationExecutor(
        codeUnitThreshold: 0,
        worker: (input) {
          final result = Completer<ForumHtmlPreparedRenderDocument>();
          pending.add((input: input, result: result));
          return result.future;
        },
      );
      addTearDown(store.clear);
      addTearDown(container.dispose);
      addTearDown(executor.dispose);
      final post = _post('native', 1, units: 8);
      final presentation = store.obtain(post.pid, post.message);
      final theme = ThemeData.light();
      var shown = true;
      Widget scene() => UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: shown
                    ? ThreadPostHtmlFirstBody(
                        nativeBody: true,
                        post: post,
                        threadId: '100',
                        imageReferer: '',
                        onOpenPostLink: (_) {},
                        onOpenPostImage: null,
                        theme: const ForumHtmlRenderThemeFactory()
                            .fromMaterialTheme(
                              theme: theme,
                              surface: theme.colorScheme.surface,
                            ),
                        preparationExecutor: executor,
                        wholeBodyPresentation: presentation,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene());
      await _until(tester, () => pending.length == 1);
      pending.first.result.complete(pending.first.input.prepare());
      await _until(
        tester,
        () => tester
            .widgetList<ForumBodyFlowBox>(find.byType(ForumBodyFlowBox))
            .any((box) => box.prefix.isComplete && box.isCurrentLayout),
      );
      final waiting = find.byType(ThreadBodyWaitingLayout);
      final height = tester.getSize(waiting).height;
      final lease = tester.widget<ThreadBodyWaitingLayout>(waiting).lease;
      final session = tester
          .widget<ForumBodyFlowBox>(find.byType(ForumBodyFlowBox))
          .session;
      expect(height, greaterThan(300));
      expect(lease.height, closeTo(height, .01));
      shown = false;
      await tester.pumpWidget(scene());
      expect(session.isClosed, isTrue);
      expect(session.activeIssuedFragments, 0);
      shown = true;
      await tester.pumpWidget(scene());
      expect(tester.getSize(waiting).height, closeTo(height, .01));
      await _until(
        tester,
        () => tester
            .widgetList<ForumBodyFlowBox>(find.byType(ForumBodyFlowBox))
            .any((box) => box.prefix.isComplete && box.isCurrentLayout),
      );
      expect(tester.getSize(waiting).height, closeTo(height, .01));
      expect(pending, hasLength(1));
      expect(store.nativeCache.preparedHits, greaterThan(0));
      expect(store.nativeCache.documentHits, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cold preparation remount preserves completed height and fold', (
    tester,
  ) async {
    final store = ThreadBodyPresentationStore();
    addTearDown(store.clear);
    final pending =
        <
          ({
            ForumHtmlBackgroundPreparationInput input,
            Completer<ForumHtmlPreparedRenderDocument> result,
          })
        >[];
    final executor = ForumHtmlPreparationExecutor(
      codeUnitThreshold: 0,
      worker: (input) {
        final result = Completer<ForumHtmlPreparedRenderDocument>();
        pending.add((input: input, result: result));
        return result.future;
      },
    );
    addTearDown(executor.dispose);
    final container = _container();
    addTearDown(container.dispose);
    final post = _post('one', 1, units: 30);
    final value = store.obtain(post.pid, post.message);
    var show = true;
    var width = 360.0;
    final theme = ThemeData.light();
    Widget host() => UncontrolledProviderScope(
      container: container,
      child: LocalizedTestApp(
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: show
                  ? ThreadPostHtmlFirstBody(
                      post: post,
                      threadId: '100',
                      imageReferer: '',
                      onOpenPostLink: (_) {},
                      onOpenPostImage: null,
                      theme: const ForumHtmlRenderThemeFactory()
                          .fromMaterialTheme(
                            theme: theme,
                            surface: theme.colorScheme.surface,
                          ),
                      preparationExecutor: executor,
                      wholeBodyPresentation: value,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(host());
    await _until(tester, () => pending.length == 1);
    pending[0].result.complete(pending[0].input.prepare());
    await _until(tester, () => _foldToggle('one').evaluate().isNotEmpty);
    await tester.tap(_foldToggle('one'));
    await tester.pumpAndSettle();
    final completedHeight = tester
        .getSize(find.byType(ThreadBodyWaitingLayout))
        .height;
    expect(completedHeight, greaterThan(400));
    final firstLease = tester
        .widget<ThreadBodyWaitingLayout>(find.byType(ThreadBodyWaitingLayout))
        .lease;
    expect(firstLease.height, completedHeight);
    expect(firstLease.rendering.collapseExpansion.values, [true]);
    final expansion = Map<String, bool>.of(
      firstLease.rendering.collapseExpansion,
    );
    final preferences = container
        .read(forumHtmlReaderPreferencesControllerProvider)
        .requireValue;
    (container.read(
      forumHtmlReaderPreferencesControllerProvider.notifier,
    ) as _Preferences).replace(
      preferences.copyWith(conversionMode: TextConversionMode.toSimplified),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ThreadBodyWaitingLayout>(find.byType(ThreadBodyWaitingLayout))
          .lease,
      same(firstLease),
    );
    show = false;
    await tester.pumpWidget(host());
    await _until(tester, () => executor.activeCount == 0);
    expect(firstLease.isCurrent, false);
    // Exercise a real cold remount after reusable inputs have been trimmed.
    store.trimNativeCache();
    show = true;
    await tester.pumpWidget(host());
    await _until(tester, () => pending.length == 2);
    expect(
      tester.getSize(find.byType(ThreadBodyWaitingLayout)).height,
      completedHeight,
    );
    expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
    pending[1].result.complete(pending[1].input.prepare());
    await _until(
      tester,
      () => _nativeText('fold-content-one').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(ThreadBodyWaitingLayout)).height,
      closeTo(completedHeight, .1),
    );
    width = 160;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final resized = tester
        .widget<ThreadBodyWaitingLayout>(find.byType(ThreadBodyWaitingLayout))
        .lease;
    expect(resized, isNot(same(firstLease)));
    expect(resized.rendering.collapseExpansion, expansion);
    expect(resized.height, greaterThan(completedHeight));
    firstLease.recordHeight(1);
    expect(resized.height, greaterThan(completedHeight));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ordinary whole cards release trees and preserve fold/footer on return',
    (tester) async {
      final host = _PageHost();
      addTearDown(host.dispose);
      await tester.pumpWidget(host.widget());
      await _until(tester, () => _body(tester, 'one') != null);
      await tester.pumpAndSettle();
      final body = _body(tester, 'one')!;
      final pure = body.wholeBodyPresentation!;
      await tester.tap(_foldToggle('one'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('thread-post-comment-header')).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('thread-post-comment-header')).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('comment-one', skipOffstage: false), findsNothing);
      await _scrollTo(tester, host.controller, 'four-unit[0]', 1);
      await tester.pumpAndSettle();
      expect(_body(tester, 'one'), isNull);
      expect(pure.isActive, true);
      await _scrollTo(tester, host.controller, 'one-unit[0]', -1);
      await tester.pumpAndSettle();
      expect(_body(tester, 'one')!.wholeBodyPresentation, same(pure));
      expect(_nativeText('fold-content-one'), findsOneWidget);
      expect(find.text('comment-one', skipOffstage: false), findsNothing);
      host.posts = [_post('one', 1, units: 35, prefix: 'replacement-')];
      host.notifyListeners();
      await _until(
        tester,
        () =>
            _body(tester, 'one')?.post.message.contains('replacement-') == true,
      );
      await tester.pumpAndSettle();
      expect(pure.isActive, false);
      expect(_nativeText('fold-content-one'), findsNothing);
      final replacement = _body(tester, 'one')!.wholeBodyPresentation!;
      host.page = 2;
      host.notifyListeners();
      await tester.pumpAndSettle();
      expect(replacement.isActive, false);
      final secondPage = _body(tester, 'one')!.wholeBodyPresentation!;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(secondPage.isActive, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'untracked source coordinator preserves original whole-card keepalive',
    (tester) async {
      final host = _PageHost(sourceReading: true);
      addTearDown(host.dispose);
      await tester.pumpWidget(host.widget());
      await _until(tester, () => _body(tester, 'one') != null);
      await tester.pumpAndSettle();
      final pure = _body(tester, 'one')!.wholeBodyPresentation!;
      expect(find.byType(ThreadBodyWaitingLayout), findsNothing);
      await tester.tap(_foldToggle('one'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, host.controller, 'four-unit[0]', 1);
      expect(_body(tester, 'one'), isNotNull);
      expect(_body(tester, 'one')!.wholeBodyPresentation, same(pure));
      expect(find.byType(ThreadBodyWaitingLayout), findsNothing);
      await _scrollTo(tester, host.controller, 'one-unit[0]', -1);
      expect(_nativeText('fold-content-one'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}

class _Preferences extends ForumHtmlReaderPreferencesController {
  @override
  Future<ForumHtmlReaderPreferences> build() async =>
      ForumHtmlReaderPreferences.defaults();
  void replace(ForumHtmlReaderPreferences preferences) =>
      state = AsyncData(preferences);
}

ProviderContainer _container() => ProviderContainer(
  overrides: [
    forumHtmlReaderPreferencesControllerProvider.overrideWith(_Preferences.new),
  ],
);

class _PageHost extends ChangeNotifier {
  _PageHost({bool sourceReading = false, this.nativeBody = false}) {
    if (sourceReading) {
      coordinator = ThreadBodyReadingCoordinator(
        observer: _Untracked(),
        scrollController: controller,
        initialTargetPid: null,
      );
    }
  }
  final container = _container();
  final controller = ScrollController();
  final bool nativeBody;
  late final quick = ThreadDetailQuickScrollCoordinator(
    scrollController: controller,
  );
  ThreadBodyReadingCoordinator? coordinator;
  var posts = [
    _post('one', 1),
    _post('two', 2),
    _post('three', 3),
    _post('four', 4),
  ];
  var page = 1;

  Widget widget() => UncontrolledProviderScope(
    container: container,
    child: AnimatedBuilder(
      animation: this,
      builder: (context, _) => LocalizedTestApp(
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 600,
              child: ThreadDetailContent(
                nativeBody: nativeBody,
                quickScrollCoordinator: quick,
                key: const ValueKey('same-owner'),
                state:
                    ThreadDetailPageState.initial(
                      tid: '100',
                      subject: 'local',
                    ).copyWith(
                      posts: posts,
                      currentPage: page,
                      lastPage: page,
                      hasMore: false,
                      isLoadingInitial: false,
                    ),
                scrollController: controller,
                bodyReadingCoordinator: coordinator,
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
    ),
  );

  @override
  void dispose() {
    quick.dispose();
    coordinator?.dispose();
    controller.dispose();
    container.dispose();
    super.dispose();
  }
}

class _Untracked implements ThreadBodyReadingObserver {
  @override
  bool tracks(String tid, String pid) => false;
  @override
  ThreadBodyRestoreTarget? restoreTarget({
    required String tid,
    required String pid,
    required Object bodyIdentity,
  }) => null;
  @override
  void onContentChanged(Object contentIdentity) {}
  @override
  void onViewport(ThreadBodyReadingViewport viewport) {}
  @override
  void onVisibility({required bool frontmost, required bool resumed}) {}
  @override
  void cancelPendingCompletion() {}
  @override
  Future<void> flush() async {}
  @override
  void retire() {}
}

ThreadPost _post(
  String pid,
  int number, {
  int units = 50,
  String prefix = '',
}) => ThreadPost(
  pid: pid,
  number: number,
  isFirst: number == 1,
  author: 'local',
  authorId: '',
  dateline: 'local',
  message:
      '<div><p>$prefix$pid-unit[0]</p>'
      '<div class="showcollapse_box" id="fold">'
      '<div class="showcollapse_title">fold</div>'
      '<div class="showcollapse_content">fold-content-$pid</div></div>'
      '${[for (var i = 1; i < units; i++) '<p>$prefix$pid-unit[$i] ${'reading text ' * 3}</p>'].join()}</div>',
  comments: [
    ThreadPostCommentEntry(
      author: 'local',
      message: 'comment-$pid',
      dateline: 'local',
    ),
  ],
);

Finder _foldToggle(String pid) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is ThreadPostHtmlFirstBody && widget.post.pid == pid,
  ),
  matching: find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('forum-native-collapse-toggle-');
  }),
);

Finder _nativeText(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is ForumBodyParagraphSurface &&
      widget.lease.isActive &&
      widget.lease.content.projection.text.contains(text),
);

ThreadPostHtmlFirstBody? _body(WidgetTester tester, String pid) {
  final bodies = tester
      .widgetList<ThreadPostHtmlFirstBody>(
        find.byType(ThreadPostHtmlFirstBody, skipOffstage: false),
      )
      .where((widget) => widget.post.pid == pid);
  return bodies.isEmpty ? null : bodies.first;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 400; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    if (ready()) return;
  }
  throw StateError('Body did not become ready');
}

Future<void> _scrollTo(
  WidgetTester tester,
  ScrollController controller,
  String marker,
  int direction,
) async {
  for (var i = 0; i < 200; i++) {
    final matches = _nativeText(marker);
    final viewport = tester.getRect(
      find.byKey(const Key('thread-detail-list')),
    );
    for (final element in matches.evaluate()) {
      final object = element.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) continue;
      var painted = true;
      RenderObject? cursor = object;
      while (cursor != null) {
        final data = cursor.parentData;
        if (data is SliverMultiBoxAdaptorParentData && data.keptAlive ||
            cursor is RenderOffstage && cursor.offstage) {
          painted = false;
        }
        cursor = cursor.parent;
      }
      if (painted &&
          viewport.overlaps(object.localToGlobal(Offset.zero) & object.size)) {
        return;
      }
    }
    controller.jumpTo(
      (controller.offset + direction * 260)
          .clamp(
            controller.position.minScrollExtent,
            controller.position.maxScrollExtent,
          )
          .toDouble(),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
  throw StateError('Continuous test scroll did not reach $marker');
}
