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
import 'package:y300/features/thread/presentation/services/thread_body_reading_coordinator.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
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
    await _until(
      tester,
      () => find
          .byKey(const Key('forum-html-collapse-toggle-one-fold'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-one-fold')),
    );
    await tester.pumpAndSettle();
    final completedHeight = tester
        .getSize(find.byType(ThreadBodyWaitingLayout))
        .height;
    expect(completedHeight, greaterThan(400));
    final firstLease = tester
        .widget<ThreadBodyWaitingLayout>(find.byType(ThreadBodyWaitingLayout))
        .lease;
    expect(firstLease.height, completedHeight);
    expect(firstLease.rendering.collapseExpansion['one-fold'], true);
    final preferences = container
        .read(forumHtmlReaderPreferencesControllerProvider)
        .requireValue;
    (container.read(forumHtmlReaderPreferencesControllerProvider.notifier)
            as _Preferences)
        .replace(
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
      () => find
          .byKey(const Key('forum-html-collapse-content-one-fold'))
          .evaluate()
          .isNotEmpty,
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
    expect(resized.rendering.collapseExpansion['one-fold'], true);
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
      await tester.tap(
        find.byKey(const Key('forum-html-collapse-toggle-one-fold')),
      );
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
      expect(
        find.byKey(const Key('forum-html-collapse-content-one-fold')),
        findsOneWidget,
      );
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
      expect(
        find.byKey(const Key('forum-html-collapse-content-one-fold')),
        findsNothing,
      );
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
      expect(_body(tester, 'one')!.wholeBodyPresentation, isNull);
      await tester.tap(
        find.byKey(const Key('forum-html-collapse-toggle-one-fold')),
      );
      await tester.pumpAndSettle();
      await _scrollTo(tester, host.controller, 'four-unit[0]', 1);
      expect(_body(tester, 'one'), isNotNull);
      expect(_body(tester, 'one')!.wholeBodyPresentation, isNull);
      await _scrollTo(tester, host.controller, 'one-unit[0]', -1);
      expect(
        find.byKey(const Key('forum-html-collapse-content-one-fold')),
        findsOneWidget,
      );
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
  _PageHost({bool sourceReading = false}) {
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
    final matches = find.textContaining(marker, findRichText: true);
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
