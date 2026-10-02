import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_card.dart';
import 'package:y300/features/comic/presentation/comic_comment_presentation_store.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    hide ThreadPostRatingsRepository;
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projector.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_content_projection_controller.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_interaction_controller.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_tail_surface.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';

import '../../../../test_support/localized_test_app.dart';
import '../../data/comic_comment_fixtures.dart';
import '../../domain/services/comic_title_parser_cases.dart';

void main() {
  for (final count in [20, 200, 1000]) {
    testWidgets(
      '$count text comments do not rebuild stable rows while dragging or coasting',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'reader_pref_mode': 'vertical',
        });
        final fixture = _Fixture(
          CommentDetailRepository(
            respond: (_) => commentDetailPage(
              lastPage: 1,
              posts: List.generate(
                count,
                (i) => commentPost(
                  i + 1,
                  message:
                      '<p>comment ${i + 1}</p><blockquote>quoted text</blockquote><p>body</p>',
                ),
              ),
            ),
          ),
        );
        addTearDown(fixture.dispose);
        await fixture.session.load();
        await tester.pumpWidget(fixture.host());
        await _pumpFrames(tester);
        final scroll = fixture.scroll(tester);
        scroll.jumpTo(8600);
        await _pumpFrames(tester);

        final tracked = <Element>{
          ...find.byType(ComicCommentCard).evaluate(),
          ...find.byType(ThreadPostHtmlFirstBody).evaluate(),
        };
        expect(tracked, isNotEmpty);
        expect(find.byType(ComicCommentCard).evaluate().length, lessThan(20));
        final rebuilds = <Element, int>{};
        var engineRebuilds = 0;
        final previousHook = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          previousHook?.call(element, builtOnce);
          if (element.widget is ImageReaderEngine) engineRebuilds++;
          if (tracked.contains(element)) {
            rebuilds.update(element, (n) => n + 1, ifAbsent: () => 1);
          }
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previousHook);

        final initialOffset = scroll.offset;
        final gesture = await tester.startGesture(const Offset(400, 350));
        for (var i = 0; i < 30; i++) {
          await gesture.moveBy(const Offset(0, -3));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(scroll.offset, greaterThan(initialOffset + 30));
        await gesture.up();
        await tester.fling(
          find.byKey(const Key('comment-stability-list')),
          const Offset(0, -100),
          500,
        );
        final releasedOffset = scroll.offset;
        for (var i = 0; i < 90; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(scroll.offset, greaterThan(releasedOffset + 1));
        expect(engineRebuilds, 0);
        final retained = tracked.where((element) => element.mounted).toList();
        expect(retained, isNotEmpty);
        for (final element in retained) {
          expect(
            rebuilds[element] ?? 0,
            0,
            reason:
                'Stable ${element.widget.runtimeType} must not rebuild for scroll ticks.',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'paged long bodies retain their measured height when recycled above the viewport',
    (tester) async {
      SharedPreferences.setMockInitialValues({'reader_pref_mode': 'ltr'});
      final trace = _RecordingScrollController();
      final fixture = _Fixture(
        CommentDetailRepository(
          respond: (_) => commentDetailPage(
            lastPage: 1,
            posts: List.generate(
              30,
              (i) => commentPost(
                i + 1,
                message:
                    '<p>floor ${i + 1}</p>${List.filled(6, '<p>paragraph</p>').join()}<!--${'x' * 10500}-->',
              ),
            ),
          ),
        ),
        scrollController: trace,
      );
      addTearDown(fixture.dispose);
      await fixture.session.load();
      await tester.pumpWidget(fixture.host());
      await _pumpFrames(tester);
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(10);
      await _settleAsyncBodies(tester);
      final first = find.byKey(const Key('comic-comment-card-1'));
      final before = tester.getSize(first).height;
      final originalMount = tester.element(first);
      final scrollable = Scrollable.of(tester.element(first));
      final position = scrollable.position;
      position.jumpTo(4500);
      await _settleAsyncBodies(tester);
      expect(first, findsNothing);
      position.jumpTo(0);
      await tester.pump();
      // A recycled async HtmlWidget used to return a zero-height body here.
      expect(tester.getSize(first).height, closeTo(before, 0.5));
      expect(tester.element(first), isNot(same(originalMount)));
      final explicitJumps = trace.jumps;
      await _settleAsyncBodies(tester);
      for (var i = 0; i < 12; i++) {
        await tester.drag(
          find.byKey(const Key('comic-comment-list')),
          const Offset(0, -600),
        );
        await _settleAsyncBodies(tester);
      }
      for (var i = 0; i < 35 && position.pixels > 0.5; i++) {
        await tester.drag(
          find.byKey(const Key('comic-comment-list')),
          const Offset(0, 600),
        );
        await _settleAsyncBodies(tester);
      }
      expect(position.pixels, closeTo(0, 0.5));
      expect(
        trace.jumps,
        explicitJumps,
      ); // No application compensation while scrolling.
      final stable = position.pixels;
      final frameworkCorrections = trace.corrections.length;
      final extent = position.maxScrollExtent;
      final barHeight = tester
          .getSize(find.byKey(const Key('comic-comment-action-bar')))
          .height;
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(position.pixels, closeTo(stable, 0.5));
        expect(position.maxScrollExtent, closeTo(extent, 0.5));
        expect(trace.corrections, hasLength(frameworkCorrections));
        expect(trace.jumps, explicitJumps);
      }
      debugPrint(
        'comment recycling: remounted height=$before, offset=$stable, extent=$extent, framework corrections=${trace.corrections}, application corrections=${trace.jumps - explicitJumps}, bar=$barHeight',
      );
      position.jumpTo(500);
      await _settleAsyncBodies(tester);
      final returnOffset = position.pixels;
      final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
      pages.jumpToPage(7);
      await _pumpFrames(tester);
      pages.jumpToPage(10);
      await _settleAsyncBodies(tester);
      expect(
        Scrollable.of(
          tester.element(find.byKey(const Key('comic-comment-card-2'))),
        ).position,
        same(position),
      );
      expect(position.pixels, closeTo(returnOffset, 0.5));
      expect(find.byType(ThreadPostHtmlFirstBody), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'folds and expanded ratings survive recycling, append and account reset',
    (tester) async {
      SharedPreferences.setMockInitialValues({'reader_pref_mode': 'ltr'});
      final ratings = _RatingsRepository();
      final longBody =
          '<div id="fold" class="showcollapse_box">'
          '<div class="showcollapse_title">fold title</div>'
          '<div class="showcollapse_content"><p>fold content</p><p>${'long body text ' * 800}</p></div></div>';
      final fixture = _Fixture(
        CommentDetailRepository(
          respond: (page) => commentDetailPage(
            page: page,
            lastPage: 2,
            posts: List.generate(
              20,
              (i) => commentPost(
                (page - 1) * 20 + i + 1,
                message: page == 1 && i == 0
                    ? longBody
                    : '<p>body ${page * 20 + i}</p>',
              ),
            ),
          ),
        ),
        ratings: ratings,
      );
      addTearDown(fixture.dispose);
      await fixture.session.load();
      await tester.pumpWidget(fixture.host());
      await _pumpFrames(tester);
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(10);
      await _settleAsyncBodies(tester);
      final first = find.byKey(const Key('comic-comment-card-1'));
      final position = Scrollable.of(tester.element(first)).position;
      await tester.tap(
        find.byKey(const Key('forum-html-collapse-toggle-1-fold')),
      );
      await _settleAsyncBodies(tester);
      final card = tester.widget<ThreadPostCard>(first);
      card.onLoadAllRatings!(card.post);
      await _settleAsyncBodies(tester);
      expect(ratings.calls, 1);
      expect(find.text('expanded reason', findRichText: true), findsOneWidget);
      final height = tester.getSize(first).height;
      position.jumpTo(height + 2500);
      await _settleAsyncBodies(tester);
      expect(first, findsNothing);
      await fixture.session.loadMore();
      await _settleAsyncBodies(tester);
      position.jumpTo(0);
      await tester.pump();
      expect(tester.getSize(first).height, closeTo(height, 0.5));
      await _settleAsyncBodies(tester);
      expect(find.text('fold content', findRichText: true), findsOneWidget);
      expect(find.text('expanded reason', findRichText: true), findsOneWidget);
      expect(ratings.calls, 1);
      expect(find.byType(ThreadPostCard).evaluate().length, lessThan(15));
      await fixture.session.resetSession();
      await _settleAsyncBodies(tester);
      expect(find.text('expanded reason', findRichText: true), findsNothing);
      expect(find.text('fold content', findRichText: true), findsNothing);
      expect(
        Scrollable.of(tester.element(first)).position.pixels,
        closeTo(0, 0.5),
      );
      expect(tester.takeException(), isNull);
    },
  );
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'reader_pref_mode': 'vertical',
    }),
  );

  testWidgets('actual comment viewport never changes image progress', (
    tester,
  ) async {
    final fixture = _Fixture(
      CommentDetailRepository(respond: (_) => _page(1, lastPage: 1)),
    );
    addTearDown(fixture.dispose);
    await fixture.session.load();
    await tester.pumpWidget(fixture.host());
    await _pumpFrames(tester);
    final scroll = fixture.scroll(tester);
    scroll.jumpTo(7300); // Last image still intersects the 800 x 600 viewport.
    await _pumpFrames(tester);
    expect(fixture.capability.progress.last, 9);
    final progressCount = fixture.capability.progress.length;
    for (final offset in [8200.0, 9000.0, 9400.0]) {
      scroll.jumpTo(offset);
      await _pumpFrames(tester);
    }
    expect(fixture.capability.progress, hasLength(progressCount));
    expect(fixture.capability.progress.last, 9);
    await _expectStable(tester, scroll);
  });

  for (final shortLastPage in [true, false]) {
    testWidgets(
      'real tail settles after append and loader removal (short=$shortLastPage)',
      (tester) async {
        final pending = Completer<CommentDetailRead>();
        final repo = CommentDetailRepository(
          respond: (page) => page == 1 ? _page(1) : pending.future,
        );
        final fixture = _Fixture(repo);
        addTearDown(fixture.dispose);
        await fixture.session.load();
        await tester.pumpWidget(fixture.host());
        await _pumpFrames(tester);
        final scroll = fixture.scroll(tester);
        await _reachBottom(tester, scroll);
        expect(repo.calls, [1, 2]);
        pending.complete(_page(2, short: shortLastPage));
        await _pumpFrames(tester);
        await _reachBottom(tester, scroll);
        expect(
          fixture.tail.verticalItemCount,
          fixture.session.state.result!.items.length,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ImageReaderEngine)),
        );
        expect(find.text(l10n.comicLastEpisode), findsNothing);
        await _expectStable(tester, scroll);
        expect(repo.calls, [1, 2]);
      },
    );
  }

  testWidgets(
    'append retry and refresh feedback settle at the real reader bottom',
    (tester) async {
      var fail = true;
      final repo = CommentDetailRepository(
        respond: (page) => page == 2 && fail
            ? const DataReadFailure(
                kind: DataReadFailureKind.network,
                diagnosticMessage: 'fixture_unavailable',
              )
            : _page(page),
      );
      final fixture = _Fixture(repo);
      addTearDown(fixture.dispose);
      await fixture.session.load();
      await tester.pumpWidget(fixture.host());
      await _pumpFrames(tester);
      final scroll = fixture.scroll(tester);
      await _reachBottom(tester, scroll);
      expect(fixture.session.state.appendError, isNotNull);
      await _expectStable(tester, scroll);
      expect(repo.calls, [1, 2]);
      fail = false;
      await fixture.session.retry();
      await _pumpFrames(tester);
      await _reachBottom(tester, scroll);
      await _expectStable(tester, scroll);
      expect(repo.calls, [1, 2, 2]);

      final bar = find.byKey(const Key('comic-comment-action-bar'));
      final barHeight = tester.getSize(bar).height;
      final rows = fixture.session.state.result;
      fail = true;
      await fixture.session.refreshAfterMutation(page: 2);
      await _pumpFrames(tester);
      expect(fixture.session.state.result, same(rows));
      expect(tester.getSize(bar).height, greaterThan(barHeight));
      await _expectStable(tester, scroll);
      fail = false;
      await fixture.session.retry();
      await _pumpFrames(tester);
      await _expectStable(tester, scroll);
      expect(tester.getSize(bar).height, closeTo(barHeight, 0.5));
      expect(repo.calls, [1, 2, 2, 2, 2]);
    },
  );

  for (final mode in ['ltr', 'rtl']) {
    testWidgets('$mode no longer renders a last-episode card', (tester) async {
      SharedPreferences.setMockInitialValues({'reader_pref_mode': mode});
      final fixture = _Fixture(
        CommentDetailRepository(respond: (_) => _page(1, lastPage: 1)),
      );
      addTearDown(fixture.dispose);
      await fixture.session.load();
      await tester.pumpWidget(fixture.host());
      await _pumpFrames(tester);
      final page = tester.widget<PageView>(find.byType(PageView));
      page.controller!.jumpToPage(10);
      await _pumpFrames(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ImageReaderEngine)),
      );
      expect(find.byKey(const Key('comic-comment-list')), findsOneWidget);
      final body = tester.widget<ForumHtmlWidgetPostRenderer>(
        find.byType(ForumHtmlWidgetPostRenderer).first,
      );
      expect(body.html, contains('fixture comment paragraph'));
      expect(body.html, isNot(contains('comic-page.jpg')));
      expect(find.text(l10n.comicLastEpisode), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

CommentDetailRead _page(
  int page, {
  int lastPage = 2,
  bool short = false,
}) => commentDetailPage(
  page: page,
  lastPage: lastPage,
  posts: List.generate(
    page == 1 ? 20 : (short ? 1 : 20),
    (i) => commentPost(
      (page - 1) * 20 + i + 1,
      message:
          '<div><img src="https://example.test/comic-page.jpg"></div>'
          '${List.filled(short ? 1 : 6, '<p>fixture comment paragraph</p>').join()}',
    ),
  ),
);

Future<void> _reachBottom(WidgetTester tester, ScrollController scroll) async {
  // Lazy children replace the estimated extent as the last rows are laid out.
  for (var i = 0; i < 5; i++) {
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _settleAsyncBodies(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _expectStable(WidgetTester tester, ScrollController scroll) async {
  final samples = <(double, double, double)>[];
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    final bar = find.byKey(const Key('comic-comment-action-bar'));
    samples.add((
      scroll.offset,
      scroll.position.maxScrollExtent,
      bar.evaluate().isEmpty ? 0 : tester.getSize(bar).height,
    ));
  }
  final settled = samples.skip(30).toList();
  for (final sample in settled) {
    expect(
      sample.$1,
      closeTo(settled.first.$1, 0.5),
      reason: 'offset/extent/bar trace: $samples',
    );
    expect(sample.$2, closeTo(settled.first.$2, 0.5));
    expect(sample.$3, closeTo(settled.first.$3, 0.5));
  }
  expect(tester.takeException(), isNull);
}

class _Fixture {
  _Fixture(
    CommentDetailRepository repo, {
    ScrollController? scrollController,
    this.ratings,
  }) {
    session = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e', sourceTid: '100'),
      loader: DefaultComicCommentLoader(repository: repo),
    );
    final plain = DefaultPlainTextBatchConversionService();
    projection = ComicCommentContentProjectionController(
      session: session,
      projector: ComicCommentContentProjector(
        plainTextBatchConversionService: plain,
        htmlTextNodeConversionService: DomHtmlTextNodeConversionService(
          plainTextBatchConversionService: plain,
        ),
        diagnosticRecorder: const NoopTextConversionDiagnosticRecorder(),
      ),
      initialMode: TextConversionMode.none,
      initialConverter: const IdentityTextConverter(),
    );
    interaction = ComicCommentInteractionController(
      session: session,
      invalidateThread: (_) async {},
    );
    tail = ComicCommentTailSurface(
      presentationStore: ComicCommentPresentationStore(
        scrollController: scrollController,
      ),
      session: session,
      contentProjectionController: projection,
      imageReferer: null,
      interactionController: interaction,
    );
    tail.updateChapterImages(['https://example.test/comic-page.jpg']);
    capability = _Capability(tail);
  }
  late final ComicCommentSessionController session;
  final ThreadPostRatingsRepository? ratings;
  late final ComicCommentContentProjectionController projection;
  late final ComicCommentInteractionController interaction;
  late final ComicCommentTailSurface tail;
  late final _Capability capability;

  Widget host() => ProviderScope(
    overrides: [
      if (ratings != null)
        threadPostRatingsRepositoryProvider.overrideWithValue(ratings!),
      forumImagePrecacheServiceProvider.overrideWithValue(_Precache()),
    ],
    child: LocalizedTestApp(
      home: AnimatedBuilder(
        animation: tail,
        builder: (_, _) => ImageReaderEngine(
          listKey: const Key('comment-stability-list'),
          capability: capability,
        ),
      ),
    ),
  );
  ScrollController scroll(WidgetTester tester) => tester
      .widget<ListView>(find.byKey(const Key('comment-stability-list')))
      .controller!;
  void dispose() {
    // The engine owns disposal of its tail surface.
    interaction.dispose();
    projection.dispose();
    session.dispose();
  }
}

class _Capability extends ReaderCapability {
  _Capability(this.tailSurface);
  final List<int> progress = [];
  @override
  final ComicCommentTailSurface tailSurface;
  @override
  ReaderContent get content => ReaderContent(
    ownerId: 'comment-stability',
    items: List.generate(
      10,
      (i) => ContinuousImageItem(
        ownerId: 'comment-stability',
        id: 'image-$i',
        url: 'https://img.test/$i.jpg',
        cacheKey: 'image-$i',
        index: i,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
        knownWidth: 100,
        knownHeight: 100,
      ),
    ),
  );
  @override
  String? get imageReferer => null;
  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) =>
      const ReaderTitleSpec(title: comicInteractionThreadTitle);
  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) =>
      const ColoredBox(color: Colors.black);
  @override
  void onScrollProgress({required int index, required double offset}) =>
      progress.add(index);
  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) =>
      ImageCacheRequest(
        cacheKey: item.cacheKey,
        sourceUrl: item.url,
        ownerType: ImageCacheOwnerType.thread,
        ownerId: item.ownerId,
        role: ImageCacheRole.threadInline,
      );
}

class _Precache implements ForumImagePrecacheService {
  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async => ForumImagePrecacheResult(
    success: true,
    decoded: false,
    cacheKey: spec.cacheKey,
  );
  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async => ForumImagePrecacheResult(
    success: true,
    decoded: true,
    cacheKey: spec.cacheKey,
  );
}

class _RecordingScrollController extends ScrollController {
  _RecordingScrollController() : super(keepScrollOffset: false);
  final corrections = <double>[];
  var jumps = 0;
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _RecordingScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    owner: this,
  );
}

class _RecordingScrollPosition extends ScrollPositionWithSingleContext {
  _RecordingScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.owner,
  }) : super(initialPixels: 0, keepScrollOffset: false);
  final _RecordingScrollController owner;
  @override
  void correctBy(double correction) {
    owner.corrections.add(correction);
    super.correctBy(correction);
  }

  @override
  void jumpTo(double value) {
    owner.jumps++;
    super.jumpTo(value);
  }
}

class _RatingsRepository implements ThreadPostRatingsRepository {
  int calls = 0;
  @override
  Future<ApiResult<ThreadPostRatingDetails>> loadAll(String url) async {
    calls++;
    return const ApiSuccess(
      ThreadPostRatingDetails(
        participantCount: 2,
        totalScoreText: '+4',
        ratings: [
          ThreadPostRating(
            userName: 'another rater',
            score: '+2',
            reason: 'expanded reason',
          ),
        ],
      ),
    );
  }
}
