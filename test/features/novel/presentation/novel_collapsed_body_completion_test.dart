import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/application/novel_reading_mutation_barrier.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/domain/models/novel_source_reading_context.dart';
import 'package:y300/features/novel/presentation/adapters/novel_source_reading_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/services/thread_body_reading_coordinator.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'reading visible body end completes with a closed nested chapter catalog',
    (tester) async {
      await _readToEnd(
        tester,
        catalog: _fold(
          '${_chapterLink('102', 'chapter two')}'
          '${_fold(_chapterLink('103', 'chapter three'), id: 'later', title: 'later chapters')}',
        ),
      );
    },
  );

  testWidgets(
    'closed story text does not prevent completing the currently visible body',
    (tester) async {
      await _readToEnd(
        tester,
        catalog: _fold(
          '${_chapterLink('102', 'chapter two')}'
          '<p>Story text remains hidden inside this fold.</p>',
        ),
      );
    },
  );

  testWidgets(
    'closed unknown chapter links do not prevent visible body completion',
    (tester) async {
      await _readToEnd(
        tester,
        catalog: _fold(
          '${_chapterLink('102', 'chapter two')}'
          '${_chapterLink('999', 'unbound chapter')}',
        ),
      );
    },
  );

  testWidgets(
    'expanding long prose moves the measured end and requires reading that end',
    (tester) async {
      final longProse = List.filled(
        80,
        '<p>Expanded chapter prose now participates in the visible body.</p>',
      ).join();
      final harness = (await tester.runAsync(
        () => _Harness.create(_fold(longProse)),
      ))!;
      try {
        await tester.pumpWidget(harness.host());
        await tester.pumpAndSettle();
        final boundary = find.byType(ThreadBodyReadingBoundary);
        final collapsedHeight = tester.getSize(boundary).height;
        harness.controller.jumpTo(
          _Harness.headerHeight + collapsedHeight - 400 + 10,
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('forum-html-collapse-toggle-101-catalog')),
        );
        await tester.pumpAndSettle();
        final expandedHeight = tester.getSize(boundary).height;
        expect(expandedHeight, greaterThan(collapsedHeight + 1000));
        expect(
          find.byKey(const Key('forum-html-collapse-content-101-catalog')),
          findsOneWidget,
        );
        await tester.runAsync(() async {
          await harness.source.flush();
          final state = await harness.repository.loadWorkState(
            novelId: 'novel',
          );
          expect(state.progressByEpisode['intro']!.progressPercent, 0);
          expect(state.episodeStates['intro']?.isRead ?? false, isFalse);
        });

        // Expanding is a layout change. Visiting the previous collapsed end
        // cannot complete the longer body that is currently visible.
        await _scrollToMeasuredEnd(tester, harness, collapsedHeight);
        await tester.runAsync(() async {
          await harness.source.flush();
          final state = await harness.repository.loadWorkState(
            novelId: 'novel',
          );
          final position = state.progressByEpisode['intro']!;
          expect(position.progressPercent, greaterThan(0));
          expect(position.progressPercent, lessThan(1));
          expect(state.episodeStates['intro']?.isRead ?? false, isFalse);
        });

        await _scrollToMeasuredEnd(tester, harness, expandedHeight);
        await tester.runAsync(() async {
          await harness.source.flush();
          final state = await harness.repository.loadWorkState(
            novelId: 'novel',
          );
          expect(state.progressByEpisode['intro']!.progressPercent, 1);
          expect(state.episodeStates['intro']!.isRead, isTrue);
        });
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, harness);
      }
    },
  );

  testWidgets(
    'collapsing into the visible end needs a fresh reading scroll to complete',
    (tester) async {
      final longProse = List.filled(
        12,
        '<p>Expanded chapter prose now participates in the visible body.</p>',
      ).join();
      final harness = (await tester.runAsync(
        () => _Harness.create(_fold(longProse), proseParagraphs: 16),
      ))!;
      try {
        await tester.pumpWidget(harness.host());
        await tester.pumpAndSettle();
        final boundary = find.byType(ThreadBodyReadingBoundary);
        final collapsedHeight = tester.getSize(boundary).height;
        final toggle = find.byKey(
          const Key('forum-html-collapse-toggle-101-catalog'),
        );
        // Keep the title tappable and the eventual collapsed end inside the
        // viewport. The footer must not become the only sampled content.
        final middleOffset = _Harness.headerHeight + collapsedHeight - 300;
        harness.controller.jumpTo(middleOffset);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          tester.getSize(boundary).height,
          greaterThan(collapsedHeight + 400),
        );

        harness.controller.jumpTo(middleOffset - 70);
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(harness.viewportKey),
          const Offset(0, -90),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        late double confirmedMiddle;
        await tester.runAsync(() async {
          await harness.source.flush();
          final state = await harness.repository.loadWorkState(
            novelId: 'novel',
          );
          confirmedMiddle = state.progressByEpisode['intro']!.progressPercent;
          expect(confirmedMiddle, greaterThan(0));
          expect(confirmedMiddle, lessThan(1));
          expect(state.episodeStates['intro']?.isRead ?? false, isFalse);
        });

        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getSize(boundary).height, closeTo(collapsedHeight, .5));
        final bodyBottom = tester.getBottomLeft(boundary).dy;
        final viewportTop = tester
            .getTopLeft(find.byKey(harness.viewportKey))
            .dy;
        expect(bodyBottom, greaterThan(viewportTop));
        expect(bodyBottom, lessThan(viewportTop + 400));
        await tester.runAsync(() async {
          await harness.source.flush();
          final state = await harness.repository.loadWorkState(
            novelId: 'novel',
          );
          expect(
            state.progressByEpisode['intro']!.progressPercent,
            confirmedMiddle,
          );
          expect(state.episodeStates['intro']?.isRead ?? false, isFalse);
        });

        await tester.drag(
          find.byKey(harness.viewportKey),
          const Offset(0, -40),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() async {
          await harness.source.flush();
          final state = await harness.repository.loadWorkState(
            novelId: 'novel',
          );
          expect(state.progressByEpisode['intro']!.progressPercent, 1);
          expect(state.episodeStates['intro']!.isRead, isTrue);
        });
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, harness);
      }
    },
  );
}

Future<void> _readToEnd(WidgetTester tester, {required String catalog}) async {
  final harness = (await tester.runAsync(() => _Harness.create(catalog)))!;
  try {
    await tester.pumpWidget(harness.host());
    await tester.pumpAndSettle();
    final boundary = find.byType(ThreadBodyReadingBoundary);
    final height = tester.getSize(boundary).height;
    expect(height, greaterThan(1000));
    expect(
      find.byKey(const Key('forum-html-collapse-content-101-catalog')),
      findsNothing,
    );
    expect(find.text('chapter two'), findsNothing);

    await _scrollToMeasuredEnd(tester, harness, height);

    await tester.runAsync(() async {
      await harness.source.flush();
      final state = await harness.repository.loadWorkState(novelId: 'novel');
      final position = state.progressByEpisode['intro']!;
      expect(position.progressPercent, 1);
      expect(position.percentBasis, NovelProgressPercentBasis.bodyGeometryV1);
      expect(state.episodeStates['intro']!.isRead, isTrue);
      expect(state.recentEpisodeId, 'intro');
    });
    expect(
      find.byKey(const Key('forum-html-collapse-content-101-catalog')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  } finally {
    await _close(tester, harness);
  }
}

Future<void> _scrollToMeasuredEnd(
  WidgetTester tester,
  _Harness harness,
  double height,
) async {
  // Approach the real mounted body end, then make a genuine reading scroll.
  // Programmatic positioning alone must not supply completion authority.
  harness.controller.jumpTo(_Harness.headerHeight + height - 400 - 70);
  await tester.pumpAndSettle();
  await tester.drag(find.byKey(harness.viewportKey), const Offset(0, -90));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _close(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  harness.dispose();
  await tester.pump();
  await tester.runAsync(harness.db.close);
}

String _fold(String content, {String id = 'catalog', String title = '目录'}) =>
    '<div class="showcollapse_box" id="$id">'
    '<div class="showcollapse_title">$title</div>'
    '<div class="showcollapse_content">$content</div>'
    '</div>';

String _chapterLink(String pid, String title) =>
    '<a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=100&amp;pid=$pid">$title</a><br>';

final class _Harness {
  _Harness(this.db, this.repository, this.committer, this.source, this.html) {
    coordinator = ThreadBodyReadingCoordinator(
      observer: source,
      scrollController: controller,
      initialTargetPid: '101',
    );
  }

  static const headerHeight = 140.0;
  final Database db;
  final LocalNovelRepository repository;
  final DefaultNovelReaderProgressCommitter committer;
  final NovelSourceReadingAdapter source;
  final String html;
  final controller = ScrollController();
  final viewportKey = GlobalKey();
  final _contentIdentity = Object();
  late final ThreadBodyReadingCoordinator coordinator;

  static Future<_Harness> create(
    String catalog, {
    int proseParagraphs = 40,
  }) async {
    final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
    final repository = LocalNovelRepository(Future.value(db));
    final committer = DefaultNovelReaderProgressCommitter(
      repository: repository,
    );
    final source = NovelSourceReadingAdapter(
      context: NovelSourceReadingContext(
        novelId: 'novel',
        initialEpisodeId: 'intro',
        chapters: const [
          NovelSourceReadingChapter(
            episodeId: 'intro',
            sourceTid: '100',
            sourcePid: '101',
          ),
          NovelSourceReadingChapter(
            episodeId: 'two',
            sourceTid: '100',
            sourcePid: '102',
          ),
          NovelSourceReadingChapter(
            episodeId: 'three',
            sourceTid: '100',
            sourcePid: '103',
          ),
        ],
      ),
      readingStateRepository: repository,
      committer: committer,
      mutationBarrier: NovelReadingMutationBarrier(),
      onCommitted: () {},
    );
    await source.prepare();
    source.onVisibility(frontmost: true, resumed: true);
    final prose = List.filled(
      proseParagraphs,
      '<p>Visible chapter prose used to measure the rendered body boundary.</p>',
    ).join();
    return _Harness(db, repository, committer, source, '$prose$catalog');
  }

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
                      const SizedBox(height: headerHeight),
                      ThreadPostHtmlFirstBody(
                        post: ThreadPost(
                          pid: '101',
                          author: 'author',
                          authorId: '1',
                          message: html,
                          number: 1,
                          isFirst: true,
                          dateline: 'date',
                        ),
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
    source.dispose();
    committer.cancel();
    controller.dispose();
  }
}
