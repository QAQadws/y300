import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' as riverpod_misc;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/cache/domain/services/native_page_cache_invalidation_service.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_diagnostic_recorder.dart';
import 'package:y300/features/history/domain/services/history_visit_recorder.dart';
import 'package:y300/features/library_shared/presentation/controllers/sync_diagnostic_mode_controller.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_notification_service.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/reply/data/providers/reply_providers.dart';
import 'package:y300/features/reply/data/repositories/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/tags/data/repositories/forum_tag_repository.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/tags/data/repositories/yamibo_tag_thread_page_repository.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';
import 'package:y300/features/tags/domain/models/yamibo_tag_thread_page.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/providers/thread_favorite_providers.dart';
import 'package:y300/features/thread/data/repositories/thread_detail_diagnostic_settings_repository.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/data/repositories/thread_post_comment_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_post_rate_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_poll_vote_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';
import 'package:y300/features/thread/domain/models/thread_detail_diagnostic_event.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/services/thread_detail_diagnostic_recorder.dart';
import 'package:y300/features/thread/domain/services/thread_favorite_action_service.dart';
import 'package:y300/features/thread/presentation/thread_detail_diagnostic_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_author_color_parser.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/thread_image_reader_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ThreadDetailPage', () {
    test('light chip background follows forum list thread tag chip', () {
      final theme = AppTheme.light();
      final detailPalette = ThreadDetailNativePalette.resolve(theme);
      final displayPalette = ForumDisplayThemePalette.resolve(theme);

      expect(
        detailPalette.chipBackground,
        displayPalette.surfaceContainerHigh.withValues(alpha: 0.42),
      );
    });

    testWidgets('shows posts and switches thread pages', (tester) async {
      var callCount = 0;
      final repository = _FakeThreadRepository((tid, page, query) async {
        callCount++;
        if (page == 1) {
          return ApiSuccess(
            ThreadDetailData(
              tid: tid,
              fid: '2',
              typeid: '410',
              typeName: '理性探讨',
              forumName: '海域區',
              forumUrl:
                  'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=33',
              subject: '测试主题',
              author: 'alice',
              replies: 1,
              views: 12,
              currentPage: 1,
              lastPage: 2,
              nextPageUrl:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=2',
              reverseOrderUrl:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&ordertype=1',
              onlyAuthorUrl:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&authorid=1',
              favoriteUrl:
                  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&type=thread&id=100',
              shareUrl:
                  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=share&type=thread&id=100',
              homeUrl: 'https://bbs.yamibo.com/index.php',
              desktopUrl:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
              perPage: 1,
              posts: [
                ThreadPost(
                  pid: 'p1',
                  author: 'alice',
                  authorId: '1',
                  message: '<p>第一条回复</p>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                  rateUrl:
                      'https://bbs.yamibo.com/forum.php?mod=misc&action=rate',
                  commentUrl:
                      'https://bbs.yamibo.com/forum.php?mod=misc&action=comment',
                  replyUrl:
                      'https://bbs.yamibo.com/forum.php?mod=post&action=reply',
                  comments: const <ThreadPostCommentEntry>[
                    ThreadPostCommentEntry(
                      author: '花実',
                      authorId: '231169',
                      avatarUrl:
                          'https://bbs.yamibo.com/uc_server/data/avatar/000/23/11/69_avatar_small.jpg',
                      message: '活该你日和你国同性恋权益烂的要死',
                      dateline: '2026-6-21 12:31',
                    ),
                  ],
                  ratingSummary: const ThreadPostRatingSummary(
                    participantText: '参与人数 1',
                    scoreText: '积分 +2',
                    viewAllUrl:
                        'https://bbs.yamibo.com/forum.php?mod=misc&action=viewratings',
                    ratings: <ThreadPostRating>[
                      ThreadPostRating(
                        userName: '子子子车',
                        userId: '736594',
                        score: '+ 2',
                        reason: '我很赞同',
                      ),
                    ],
                  ),
                  poll: const ThreadPoll(
                    isMultipleChoice: false,
                    summary: '单选投票 , 投票后结果可见, 共有 2 人参与投票',
                    actionUrl:
                        'https://bbs.yamibo.com/forum.php?mod=misc&action=votepoll&tid=100',
                    formHash: 'fh_poll',
                    options: <ThreadPollOption>[
                      ThreadPollOption(id: '1', label: '选项A'),
                      ThreadPollOption(id: '2', label: '选项B'),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '2',
            subject: '测试主题',
            author: 'alice',
            replies: 1,
            views: 12,
            currentPage: 2,
            lastPage: 2,
            previousPageUrl:
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
            reverseOrderUrl: null,
            onlyAuthorUrl: null,
            shareUrl:
                'https://bbs.yamibo.com/home.php?mod=spacecp&ac=share&type=thread&id=100',
            homeUrl: 'https://bbs.yamibo.com/index.php',
            desktopUrl:
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=2',
            perPage: 1,
            posts: [
              ThreadPost(
                pid: 'p2',
                author: 'bob',
                authorId: '2',
                message: '<div>第二条回复</div>',
                number: 2,
                isFirst: false,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('thread-detail-list')), findsOneWidget);
      expect(find.text('海域區'), findsOneWidget);
      expect(_appBarTitleText('海域區'), findsOneWidget);
      expect(_appBarTitleText('测试主题'), findsNothing);
      expect(
        find.byKey(const Key('thread-detail-appbar-reply-button')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.reply), findsOneWidget);
      expect(find.byIcon(Icons.star_border_outlined), findsOneWidget);
      expect(find.byKey(const Key('thread-detail-share-button')), findsNothing);
      expect(
        _centerDxOf(
          tester,
          find.byKey(const Key('thread-detail-favorite-button')),
        ),
        lessThan(
          _centerDxOf(
            tester,
            find.byKey(const Key('thread-detail-appbar-reply-button')),
          ),
        ),
      );
      expect(find.byKey(const Key('thread-detail-header-card')), findsNothing);
      expect(
        find.byKey(const Key('thread-detail-first-post-summary')),
        findsOneWidget,
      );
      expect(find.text('理性探讨'), findsNothing);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('第 1 / 2 页'), findsNothing);
      expect(find.byKey(const Key('thread-post-card-p1')), findsOneWidget);
      expect(find.byType(ThreadPostCard), findsNothing);
      final postCard = tester.widget<Container>(
        find.byKey(const Key('thread-post-card-p1')),
      );
      final postCardDecoration = postCard.decoration as BoxDecoration;
      final detailPalette = ThreadDetailNativePalette.resolve(
        Theme.of(tester.element(find.byType(ThreadDetailPage))),
      );
      expect(
        postCardDecoration.boxShadow,
        ForumNativeSurfaceShadows.card(detailPalette.stateLayer),
      );
      expect(_richTextContaining('第一条回复'), findsOneWidget);
      expect(find.byKey(const Key('thread-poll-card')), findsOneWidget);
      expect(find.text('选项A'), findsOneWidget);
      final pollSubmitBeforeSelection = tester.widget<FilledButton>(
        find.byKey(const Key('thread-poll-submit-button')),
      );
      expect(pollSubmitBeforeSelection.onPressed, isNull);
      expect(find.byKey(const Key('thread-post-actions-p1')), findsNothing);
      expect(find.text('评分'), findsOneWidget);
      expect(find.text('点评'), findsOneWidget);
      expect(
        find.byKey(const Key('thread-post-comment-section')),
        findsOneWidget,
      );
      final pollCard = tester.widget<Container>(
        find.byKey(const Key('thread-poll-card')),
      );
      final pollCardDecoration = pollCard.decoration as BoxDecoration;
      expect(pollCardDecoration.color, detailPalette.panelBackground);
      expect(pollCardDecoration.border, isNull);
      final pollSummaryText = tester.widget<Text>(
        find.text('单选投票 , 投票后结果可见, 共有 2 人参与投票'),
      );
      expect(pollSummaryText.style?.fontWeight, FontWeight.w500);
      final pollOptionText = tester.widget<Text>(find.text('选项A'));
      expect(pollOptionText.style?.fontWeight, FontWeight.w400);

      await tester.tap(find.byKey(const Key('thread-poll-header')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('选项A'), findsNothing);
      expect(find.byKey(const Key('thread-poll-submit-button')), findsNothing);
      expect(find.text('2项'), findsNothing);
      expect(find.text('2人'), findsNothing);

      await tester.tap(find.byKey(const Key('thread-poll-header')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('选项A'), findsOneWidget);
      expect(
        find.byKey(const Key('thread-poll-submit-button')),
        findsOneWidget,
      );
      final commentSection = tester.widget<Container>(
        find.byKey(const Key('thread-post-comment-section')),
      );
      final commentSectionDecoration =
          commentSection.decoration as BoxDecoration;
      expect(commentSectionDecoration.color, detailPalette.panelBackground);
      expect(find.text('花実'), findsOneWidget);
      expect(find.text('活该你日和你国同性恋权益烂的要死'), findsOneWidget);
      expect(find.text('2026-6-21 12:31'), findsOneWidget);
      expect(
        find.byKey(const Key('thread-post-rating-section')),
        findsOneWidget,
      );
      final ratingSection = tester.widget<Container>(
        find.byKey(const Key('thread-post-rating-section')),
      );
      final ratingSectionDecoration = ratingSection.decoration as BoxDecoration;
      expect(ratingSectionDecoration.color, detailPalette.panelBackground);
      expect(find.text('参与人数 1'), findsOneWidget);
      expect(find.text('积分 +2'), findsOneWidget);
      expect(find.text('子子子车'), findsOneWidget);
      expect(find.text('我很赞同'), findsOneWidget);
      expect(find.text('查看全部评分'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);

      await tester.tap(find.byKey(const Key('thread-post-comment-header')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('花実'), findsNothing);
      expect(find.text('活该你日和你国同性恋权益烂的要死'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('thread-post-comment-section')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('thread-post-comment-header')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('花実'), findsOneWidget);
      expect(find.text('活该你日和你国同性恋权益烂的要死'), findsOneWidget);

      await tester.tap(find.byKey(const Key('thread-post-rating-header')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('参与人数 1'), findsNothing);
      expect(find.text('积分 +2'), findsNothing);
      expect(find.text('子子子车'), findsNothing);
      expect(find.text('查看全部评分'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('thread-post-rating-section')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('thread-post-rating-section')),
          matching: find.text('+2'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('thread-post-rating-header')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('参与人数 1'), findsOneWidget);
      expect(find.text('积分 +2'), findsOneWidget);
      expect(find.text('子子子车'), findsOneWidget);
      expect(find.text('查看全部评分'), findsOneWidget);
      expect(find.byKey(const Key('thread-replies-header')), findsNothing);
      expect(find.text('全部回复'), findsNothing);
      expect(find.byKey(const Key('thread-reply-input')), findsNothing);
      expect(find.byKey(const Key('thread-reply-submit-button')), findsNothing);

      await tester.dragUntilVisible(
        find.byKey(const Key('thread-detail-load-more-button')),
        find.byKey(const Key('thread-detail-list')),
        const Offset(0, -260),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('thread-detail-load-more-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('thread-detail-current-page-button')),
        findsOneWidget,
      );
      expect(find.text('下一页'), findsOneWidget);
      final detailPageButtonKeys = [
        const Key('thread-detail-previous-page-button'),
        const Key('thread-detail-current-page-button'),
        const Key('thread-detail-load-more-button'),
      ];
      for (final key in detailPageButtonKeys) {
        final pageButton = tester.widget<TextButton>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(TextButton),
          ),
        );
        expect(
          pageButton.style?.backgroundColor?.resolve({}),
          detailPalette.chipBackground,
        );
      }
      await tester.tap(find.byKey(const Key('thread-detail-load-more-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(_richTextContaining('第一条回复'), findsNothing);
      expect(_richTextContaining('第二条回复'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('thread-post-card-p2'))).dy,
        lessThan(120),
      );
      expect(
        find.byKey(const Key('thread-detail-bottom-favorite-button')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('thread-detail-more-menu')));
      await tester.pumpAndSettle();
      expect(find.text('返回首页'), findsOneWidget);
      expect(find.text('电脑版'), findsNothing);
      expect(callCount, 2);

      await tester.tap(find.text('倒序浏览'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(repository.queryHistory.last['ordertype'], '1');
      expect(_richTextContaining('第一条回复'), findsOneWidget);
      expect(callCount, 3);
    });

    testWidgets(
      'Phase 0 baseline commits non-empty posts then changes pages in place',
      (tester) async {
        final firstPageResult = Completer<ApiResult<ThreadDetailData>>();
        final historyRecorder = _RecordingHistoryVisitRecorder();
        final historyDiagnostics = _RecordingHistoryDiagnostics();
        var callCount = 0;
        final repository = _FakeThreadRepository((tid, page, query) async {
          callCount++;
          if (page == 1) {
            return firstPageResult.future;
          }
          return ApiSuccess(
            ThreadDetailData(
              tid: tid,
              fid: '2',
              forumName: '测试版块',
              subject: '测试主题',
              author: 'alice',
              replies: 2,
              views: 12,
              currentPage: 2,
              lastPage: 2,
              previousPageUrl:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
              desktopUrl:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=2',
              perPage: 1,
              posts: <ThreadPost>[
                ThreadPost(
                  pid: 'phase0-p2',
                  author: 'bob',
                  authorId: '2',
                  message: '<p>第二页正文</p>',
                  number: 2,
                  isFirst: false,
                  dateline: 'today',
                ),
              ],
            ),
          );
        });

        await tester.pumpWidget(
          _buildTestApp(
            repository,
            historyVisitRecorder: historyRecorder,
            historyDiagnosticRecorder: historyDiagnostics,
          ),
        );
        await tester.pump();

        expect(find.byKey(const Key('thread-detail-list')), findsNothing);
        expect(callCount, 1);
        expect(historyRecorder.drafts, isEmpty);

        firstPageResult.complete(
          ApiSuccess<ThreadDetailData>(
            ThreadDetailData(
              tid: '100',
              fid: '2',
              forumName: '测试版块',
              subject: '测试主题',
              author: 'alice',
              replies: 2,
              views: 12,
              currentPage: 1,
              lastPage: 2,
              nextPageUrl:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=2',
              desktopUrl:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
              perPage: 1,
              posts: <ThreadPost>[
                ThreadPost(
                  pid: 'phase0-p1',
                  author: 'alice',
                  authorId: '1',
                  message: '<p>第一页正文</p>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                  avatarUrl: 'https://bbs.yamibo.com/avatar/alice.jpg',
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(find.byKey(const Key('thread-detail-list')), findsOneWidget);
        expect(
          find.byKey(const Key('thread-post-card-phase0-p1')),
          findsOneWidget,
        );
        expect(callCount, 1);
        expect(historyRecorder.drafts, hasLength(1));
        final draft = historyRecorder.drafts.single;
        expect(
          draft.target,
          const HistoryTargetKey(type: HistoryTargetType.thread, id: '100'),
        );
        expect(draft.title, '测试主题');
        expect(draft.forumName, '测试版块');
        expect(draft.page, 1);
        expect(draft.thumbnail, isNull);

        await tester.dragUntilVisible(
          find.byKey(const Key('thread-detail-load-more-button')),
          find.byKey(const Key('thread-detail-list')),
          const Offset(0, -260),
        );
        await tester.tap(
          find.byKey(const Key('thread-detail-load-more-button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 260));

        expect(
          find.byKey(const Key('thread-post-card-phase0-p1')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('thread-post-card-phase0-p2')),
          findsOneWidget,
        );
        expect(callCount, 2);
        expect(historyRecorder.drafts, hasLength(1));

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ThreadDetailPage)),
        );
        const args = ThreadDetailArgs(tid: '100', subject: '测试主题');
        await container
            .read(threadDetailControllerProvider(args).notifier)
            .refresh();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(historyRecorder.drafts, hasLength(1));
        expect(
          historyDiagnostics.skipReasons,
          contains('route_session_duplicate'),
        );
      },
    );

    for (final source in <String>['network', 'snapshot', 'document cache']) {
      testWidgets('records one visible visit from $source content', (
        tester,
      ) async {
        final historyRecorder = _RecordingHistoryVisitRecorder();
        final sourceId = source.replaceAll(' ', '-');
        final repository = _FakeThreadRepository((tid, page) async {
          return ApiSuccess(
            ThreadDetailData(
              tid: tid,
              fid: '2',
              forumName: '测试版块',
              subject: '$source 主题',
              author: 'alice',
              replies: 0,
              views: 1,
              currentPage: page,
              lastPage: 1,
              desktopUrl:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&page=$page',
              perPage: 20,
              posts: <ThreadPost>[
                ThreadPost(
                  pid: '$sourceId-p1',
                  author: 'alice',
                  authorId: '1',
                  message: '<p>可见正文</p>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
              ],
            ),
          );
        });

        await tester.pumpWidget(
          _buildTestApp(repository, historyVisitRecorder: historyRecorder),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(
          find.byKey(Key('thread-post-card-$sourceId-p1')),
          findsOneWidget,
        );
        expect(historyRecorder.drafts, hasLength(1));
        expect(historyRecorder.drafts.single.title, '$source 主题');
      });
    }

    testWidgets('failed initial load records only after retry succeeds', (
      tester,
    ) async {
      final historyRecorder = _RecordingHistoryVisitRecorder();
      var callCount = 0;
      final repository = _FakeThreadRepository((tid, page) async {
        callCount++;
        if (callCount == 1) {
          return const ApiFailure<ThreadDetailData>(
            ApiError(type: ApiErrorType.network, message: '加载失败'),
          );
        }
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: <ThreadPost>[
              ThreadPost(
                pid: 'retry-p1',
                author: 'alice',
                authorId: '1',
                message: '<p>重试后的正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(repository, historyVisitRecorder: historyRecorder),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-detail-retry-button')),
        findsOneWidget,
      );
      expect(historyRecorder.drafts, isEmpty);

      await tester.tap(find.byKey(const Key('thread-detail-retry-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.byKey(const Key('thread-post-card-retry-p1')),
        findsOneWidget,
      );
      expect(historyRecorder.drafts, hasLength(1));
    });

    testWidgets('history failures never replace visible thread content', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: <ThreadPost>[
              ThreadPost(
                pid: 'history-failure-p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文仍然可见</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          historyVisitRecorder: const _ThrowingHistoryVisitRecorder(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.byKey(const Key('thread-post-card-history-failure-p1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('thread-detail-retry-button')), findsNothing);
    });

    testWidgets('late content after route disposal does not record', (
      tester,
    ) async {
      final result = Completer<ApiResult<ThreadDetailData>>();
      final historyRecorder = _RecordingHistoryVisitRecorder();
      final repository = _FakeThreadRepository((tid, page) => result.future);

      await tester.pumpWidget(
        _buildTestApp(repository, historyVisitRecorder: historyRecorder),
      );
      await tester.pump();
      expect(historyRecorder.drafts, isEmpty);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      result.complete(
        ApiSuccess(
          _threadDetailData(
            tid: '100',
            posts: <ThreadPost>[
              ThreadPost(
                pid: 'late-p1',
                author: 'alice',
                authorId: '1',
                message: '<p>迟到正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(historyRecorder.drafts, isEmpty);
    });

    testWidgets('a new route records another visit to the same TID', (
      tester,
    ) async {
      final historyRecorder = _RecordingHistoryVisitRecorder();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: <ThreadPost>[
              ThreadPost(
                pid: 'route-p1',
                author: 'alice',
                authorId: '1',
                message: '<p>路由正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          historyVisitRecorder: historyRecorder,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const Key('open-native-thread-route'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const ThreadDetailPage(tid: '100', subject: '测试主题'),
                      ),
                    );
                  },
                  child: const Text('打开帖子'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-native-thread-route')));
      await tester.pumpAndSettle();
      expect(historyRecorder.drafts, hasLength(1));

      Navigator.of(tester.element(find.byType(ThreadDetailPage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-native-thread-route')));
      await tester.pumpAndSettle();

      expect(historyRecorder.drafts, hasLength(2));
      expect(
        historyRecorder.drafts.map((draft) => draft.target.id),
        everyElement('100'),
      );
    });

    testWidgets('uses HTML-first body renderer by default', (tester) async {
      final repository = _FakeThreadRepository((tid, page, query) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>默认旧正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('thread-post-body-p1')), findsOneWidget);
      expect(find.byType(ThreadPostHtmlBody), findsOneWidget);
      expect(find.byType(ThreadPostHtmlFirstBody), findsOneWidget);
      expect(_richTextContaining('默认旧正文'), findsOneWidget);
    });

    testWidgets(
      'HTML-first diagnostic renderer keeps native poll footer separate',
      (tester) async {
        final repository = _FakeThreadRepository((tid, page, query) async {
          return ApiSuccess(
            _threadDetailData(
              tid: tid,
              posts: [
                ThreadPost(
                  pid: 'p1',
                  author: 'alice',
                  authorId: '1',
                  message:
                      '<p>HTML-first 正文</p>'
                      '<div class="showcollapse_box">'
                      '<div class="showcollapse_title">目录</div>'
                      '<div class="showcollapse_content">隐藏内容</div>'
                      '</div>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                  poll: const ThreadPoll(
                    isMultipleChoice: false,
                    summary: '单选投票',
                    options: <ThreadPollOption>[
                      ThreadPollOption(id: '1', label: '投票选项'),
                    ],
                  ),
                ),
              ],
            ),
          );
        });

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(
          find.byKey(const Key('thread-post-html-first-body-p1')),
          findsOneWidget,
        );
        expect(find.byType(ThreadPostHtmlFirstBody), findsOneWidget);
        expect(find.byKey(const Key('thread-poll-card')), findsOneWidget);
        expect(find.text('投票选项'), findsOneWidget);
        expect(_richTextContaining('HTML-first 正文'), findsOneWidget);
      },
    );

    testWidgets(
      'HTML-first theme changes reprepare colors without reloading the thread',
      (tester) async {
        var requestCount = 0;
        final repository = _FakeThreadRepository((tid, page, query) async {
          requestCount++;
          return ApiSuccess(
            _threadDetailData(
              tid: tid,
              posts: [
                ThreadPost(
                  pid: 'theme-p1',
                  author: 'alice',
                  authorId: '1',
                  message: '<font id="theme-body" color="black">正文</font>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
              ],
            ),
          );
        });

        await tester.pumpWidget(
          _buildTestApp(repository, theme: AppTheme.dark()),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        final darkHtml = tester
            .widget<HtmlWidget>(
              find.byKey(const Key('forum-html-renderer-theme-p1')),
            )
            .html;
        final darkBody = const CsslibAuthorColorParser().parseOwn(
          html_parser.parseFragment(darkHtml).querySelector('#theme-body')!,
        );
        expect(darkBody.foreground?.toARGB32(), isNot(0xFF000000));
        expect(requestCount, 1);

        await tester.pumpWidget(
          _buildTestApp(repository, theme: AppTheme.light()),
        );
        await tester.pumpAndSettle();

        final lightHtml = tester
            .widget<HtmlWidget>(
              find.byKey(const Key('forum-html-renderer-theme-p1')),
            )
            .html;
        final lightBody = const CsslibAuthorColorParser().parseOwn(
          html_parser.parseFragment(lightHtml).querySelector('#theme-body')!,
        );
        expect(lightBody.foreground?.toARGB32(), 0xFF000000);
        expect(lightHtml, isNot(darkHtml));
        expect(requestCount, 1);
      },
    );

    testWidgets('HTML-first images use project cache requests', (tester) async {
      final imageCacheService = _RecordingImageCacheService();
      final repository = _FakeThreadRepository((tid, page, query) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message:
                    '<p>HTML-first 图片</p>'
                    '<img src="data/attachment/forum/page-1.jpg" width="200" height="120">'
                    '<p>表情 <img src="static/image/smiley/comcom/2.gif" alt=""></p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(repository, imageCacheService: imageCacheService),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        imageCacheService.requests.map((request) => request.role),
        containsAll(<ImageCacheRole>[
          ImageCacheRole.threadInline,
          ImageCacheRole.remoteSmiley,
        ]),
      );
      final threadImage = imageCacheService.requests.firstWhere(
        (request) => request.role == ImageCacheRole.threadInline,
      );
      expect(threadImage.ownerType, ImageCacheOwnerType.thread);
      expect(threadImage.ownerId, '100');
      expect(threadImage.sourceUrl, contains('page-1.jpg'));

      final smiley = imageCacheService.requests.firstWhere(
        (request) => request.role == ImageCacheRole.remoteSmiley,
      );
      expect(smiley.ownerType, ImageCacheOwnerType.sticker);
      expect(smiley.effectiveRetentionClass, ImageRetentionClass.sticky);
      expect(smiley.sourceUrl, contains('static/image/smiley/comcom/2.gif'));
    });

    testWidgets(
      'HTML-first image taps open reader by readable sequence index',
      (tester) async {
        final repository = _FakeThreadRepository((tid, page, query) async {
          return ApiSuccess(
            _threadDetailData(
              tid: tid,
              posts: [
                ThreadPost(
                  pid: 'p1',
                  author: 'alice',
                  authorId: '1',
                  message:
                      '<img src="https://example.com/page-same.jpg">'
                      '<img src="https://example.com/page-same.jpg">'
                      '<p>表情 <img src="static/image/smiley/comcom/2.gif"></p>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
              ],
            ),
          );
        });

        await tester.pumpWidget(
          _buildTestApp(
            repository,
            imageCacheService: _RecordingImageCacheService(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        final secondImage = find.byKey(
          const Key('thread-post-html-first-readable-image-p1-1'),
        );
        await tester.ensureVisible(secondImage);
        await tester.pump();
        await tester.tap(secondImage);
        await tester.pumpAndSettle();

        expect(find.byType(ThreadImageReaderPage), findsOneWidget);
        expect(
          find.byKey(const Key('thread-image-reader-page-view')),
          findsOneWidget,
        );
      },
    );

    testWidgets('HTML-first smiley taps do not open image reader', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page, query) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message:
                    '<p>表情 <img src="static/image/smiley/comcom/2.gif"></p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          imageCacheService: _RecordingImageCacheService(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.byKey(const Key('thread-post-html-first-readable-image-p1-0')),
        findsNothing,
      );
      expect(find.byType(ThreadImageReaderPage), findsNothing);
    });

    testWidgets('HTML-first mode triggers lightweight image preheat', (
      tester,
    ) async {
      final precacheService = _RecordingForumImagePrecacheService();
      final repository = _FakeThreadRepository((tid, page, query) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message:
                    '<p>HTML-first 图片预热</p>'
                    '<img src="data/attachment/forum/page-1.jpg">'
                    '<p>表情 <img src="static/image/smiley/comcom/2.gif"></p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(repository, forumImagePrecacheService: precacheService),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(precacheService.decodedSpecs, isNotEmpty);
      expect(
        precacheService.decodedSpecs.map((spec) => spec.kind).toSet(),
        <ForumImageKind>{ForumImageKind.threadInline},
      );
      expect(precacheService.decodedSpecs.first.sourceUrl, contains('page-1'));
    });

    testWidgets(
      'production HTML-first renderer triggers lightweight image preheat',
      (tester) async {
        final precacheService = _RecordingForumImagePrecacheService();
        final repository = _FakeThreadRepository((tid, page, query) async {
          return ApiSuccess(
            _threadDetailData(
              tid: tid,
              posts: [
                ThreadPost(
                  pid: 'p1',
                  author: 'alice',
                  authorId: '1',
                  message: '<img src="data/attachment/forum/page-1.jpg">',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
              ],
            ),
          );
        });

        await tester.pumpWidget(
          _buildTestApp(repository, forumImagePrecacheService: precacheService),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(precacheService.decodedSpecs, isNotEmpty);
        expect(
          precacheService.decodedSpecs.first.kind,
          ForumImageKind.threadInline,
        );
      },
    );

    testWidgets('long pressing app bar copies thread link', (tester) async {
      final copiedTexts = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = Map<String, dynamic>.from(call.arguments as Map);
            copiedTexts.add(data['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            forumName: '海域區',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            lastPage: 1,
            desktopUrl:
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
            perPage: 1,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>第一条回复</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.longPress(
        find.byKey(const Key('thread-detail-appbar-copy-link-area')),
      );
      await tester.pump();

      expect(copiedTexts, [
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
      ]);
      expect(find.text('帖子链接已复制'), findsOneWidget);
    });

    testWidgets('default svg author avatar uses local noavatar asset', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                avatarUrl:
                    'https://bbs.yamibo.com/uc_server/data/avatar/noavatar.svg',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == forumDefaultAvatarAsset,
        ),
        findsOneWidget,
      );
    });

    testWidgets('normal author avatar uses avatar cache request', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                avatarUrl:
                    'https://bbs.yamibo.com/uc_server/data/avatar/000/00/00/01_avatar_small.jpg',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump();

      final avatarImage = tester.widget<CachedLibraryImage>(
        find.descendant(
          of: find.byKey(const Key('thread-author-avatar-p1')),
          matching: find.byType(CachedLibraryImage),
        ),
      );
      expect(avatarImage.request?.role, ImageCacheRole.avatar);
      expect(avatarImage.request?.ownerType, ImageCacheOwnerType.thread);
      expect(avatarImage.request?.ownerId, '1');
      expect(
        avatarImage.request?.sourceUrl,
        'https://bbs.yamibo.com/uc_server/data/avatar/000/00/00/01_avatar_small.jpg',
      );
    });

    testWidgets('schedules only lightweight HTML-first post image preloads', (
      tester,
    ) async {
      final imageCacheService = _RecordingImageCacheService();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message:
                    '<img file="data/attachment/forum/page-1.jpg" />'
                    '<p>表情 <img src="static/image/smiley/comcom/2.gif" /></p>'
                    '${List.filled(80, '<p>用于把第二楼推出初始 cacheExtent 的长正文。</p>').join()}',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
              ThreadPost(
                pid: 'p2',
                author: 'bob',
                authorId: '2',
                message: '<img file="data/attachment/forum/page-2.jpg" />',
                number: 2,
                isFirst: false,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: _threadDetailOverrides(
            repository,
            imageCacheService: imageCacheService,
          ),
          child: const MaterialApp(
            home: ThreadDetailPage(tid: '100', subject: '测试主题'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(
        imageCacheService.requests.any(
          (request) => request.sourceUrl.contains('page-2.jpg'),
        ),
        isTrue,
      );
      expect(
        imageCacheService.requests
            .where((request) => request.role == ImageCacheRole.threadInline)
            .length,
        lessThanOrEqualTo(3),
      );
    });

    testWidgets('records thread detail diagnostic events when enabled', (
      tester,
    ) async {
      final recorder = InMemoryThreadDetailDiagnosticRecorder(enabled: true);
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message:
                    '<p>正文</p>'
                    '<img file="data/attachment/forum/page-1.jpg" />',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._threadDetailOverrides(repository),
            threadDetailDiagnosticRecorderProvider.overrideWithValue(recorder),
            threadDetailDiagnosticSettingsRepositoryProvider.overrideWithValue(
              _FakeThreadDetailDiagnosticSettingsRepository(enabled: true),
            ),
          ],
          child: const MaterialApp(
            home: ThreadDetailPage(tid: '100', subject: '测试主题'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final events = recorder.snapshot();
      expect(
        events.any(
          (event) =>
              event.type == ThreadDetailDiagnosticEventType.renderPlanCreate &&
              event.pid == 'p1',
        ),
        isTrue,
      );
      expect(
        events.any(
          (event) =>
              event.type == ThreadDetailDiagnosticEventType.entryBuild &&
              event.entryKey == 'thread-post-card-entry-p1',
        ),
        isTrue,
      );
      expect(
        events.any(
          (event) =>
              event.type ==
                  ThreadDetailDiagnosticEventType.htmlFirstImageDiagnostics &&
              event.message.contains('html-first-preload'),
        ),
        isTrue,
      );
      expect(recorder.exportText(), contains('html-first-preload'));
    });

    testWidgets('stretches whole post card segments to the same width', (
      tester,
    ) async {
      final state = ThreadDetailPageState.initial(tid: '100', subject: '测试主题')
          .copyWith(
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>短正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(
              _NoopImageCacheService(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ThreadDetailContent(
                state: state,
                imageHeaderBuilder: null,
                imageReferer:
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
                onLoadPreviousPage: () {},
                onLoadNextPage: () {},
                onLoadPageNumber: (_) {},
                onOpenAuthorProfile: (_) {},
                onOpenCommentAuthorProfile: (_) {},
                onCopyActionUrl: (_, _) {},
                onOpenPostLink: (_) {},
                onOpenPostActions: (_, _) {},
                onTogglePollOption: (_, _) {},
                onSubmitPollVote: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final headerWidth = tester
          .getSize(find.byKey(const Key('thread-post-card-p1')))
          .width;
      final bodyWidth = tester
          .getSize(find.byKey(const Key('thread-post-body-p1')))
          .width;
      final footerWidth = tester
          .getSize(find.byKey(const Key('thread-post-footer-p1')))
          .width;

      expect(bodyWidth, headerWidth);
      expect(footerWidth, headerWidth);
    });

    testWidgets('collapsing comments reduces post card height', (tester) async {
      final state = ThreadDetailPageState.initial(tid: '100', subject: '测试主题')
          .copyWith(
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>短正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                comments: const <ThreadPostCommentEntry>[
                  ThreadPostCommentEntry(
                    author: 'alice',
                    message: '第一条点评内容',
                    dateline: 'today',
                  ),
                  ThreadPostCommentEntry(
                    author: 'bob',
                    message: '第二条点评内容',
                    dateline: 'today',
                  ),
                  ThreadPostCommentEntry(
                    author: 'carol',
                    message: '第三条点评内容',
                    dateline: 'today',
                  ),
                ],
              ),
            ],
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(
              _NoopImageCacheService(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ThreadDetailContent(
                state: state,
                imageHeaderBuilder: null,
                imageReferer:
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
                onLoadPreviousPage: () {},
                onLoadNextPage: () {},
                onLoadPageNumber: (_) {},
                onOpenAuthorProfile: (_) {},
                onOpenCommentAuthorProfile: (_) {},
                onCopyActionUrl: (_, _) {},
                onOpenPostLink: (_) {},
                onOpenPostActions: (_, _) {},
                onTogglePollOption: (_, _) {},
                onSubmitPollVote: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      final expandedHeight = tester
          .getSize(find.byKey(const Key('thread-post-comment-section')))
          .height;

      await tester.tap(find.byKey(const Key('thread-post-comment-header')));
      await tester.pump();

      final collapsedHeight = tester
          .getSize(find.byKey(const Key('thread-post-comment-section')))
          .height;
      expect(collapsedHeight, lessThan(expandedHeight));
      expect(find.text('第一条点评内容'), findsNothing);
    });

    testWidgets(
      'ThreadDetailContent builds reader image request with thread context',
      (tester) async {
        ThreadPostImageOpenRequest? opened;
        final state = ThreadDetailPageState.initial(tid: '100', subject: '测试主题')
            .copyWith(
              currentPage: 1,
              posts: [
                ThreadPost(
                  pid: 'p1',
                  author: 'alice',
                  authorId: '1',
                  message:
                      '<img file="data/attachment/forum/page-1.jpg" width="200" height="120">'
                      '<img file="data/attachment/forum/page-2.jpg" width="200" height="120">',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
              ],
            );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              imageCacheServiceProvider.overrideWithValue(
                _NoopImageCacheService(),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ThreadDetailContent(
                  state: state,
                  imageHeaderBuilder: null,
                  imageReferer:
                      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
                  onLoadPreviousPage: () {},
                  onLoadNextPage: () {},
                  onLoadPageNumber: (_) {},
                  onOpenAuthorProfile: (_) {},
                  onOpenCommentAuthorProfile: (_) {},
                  onCopyActionUrl: (_, _) {},
                  onOpenPostLink: (_) {},
                  onOpenPostImages: (_, request) => opened = request,
                  onOpenPostActions: (_, _) {},
                  onTogglePollOption: (_, _) {},
                  onSubmitPollVote: (_) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(ThreadPostHtmlBody), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('thread-post-html-first-readable-image-p1-0')),
        );
        await tester.pump();

        final readerRequest = opened?.readerRequest;
        expect(readerRequest, isNotNull);
        expect(readerRequest!.tid, '100');
        expect(readerRequest.pid, 'p1');
        expect(readerRequest.postNumber, 1);
        expect(
          readerRequest.referer,
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
        );
        expect(readerRequest.initialIndex, 0);
        expect(readerRequest.group.entries, hasLength(2));
        expect(
          readerRequest.initialEntry?.cacheKey,
          startsWith('thread/inline/'),
        );
        expect(
          readerRequest.initialEntry?.url,
          'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
        );
        expect(readerRequest.continuousImages, hasLength(2));
        expect(
          readerRequest.continuousImages.first.sourceKind,
          ContinuousImageSourceKind.threadImageReader,
        );
        expect(
          readerRequest.continuousImages.first.cacheKey,
          readerRequest.initialEntry?.cacheKey,
        );
      },
    );

    testWidgets('opens thread image reader page when tapping post image', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message:
                    '<img file="data/attachment/forum/page-1.jpg" width="200" height="120">'
                    '<img file="data/attachment/forum/page-2.jpg" width="200" height="120">',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('thread-post-html-first-readable-image-p1-0')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ThreadImageReaderPage), findsOneWidget);
      expect(
        find.byKey(const Key('thread-image-reader-page-view')),
        findsOneWidget,
      );
      expect(find.text('图片阅读'), findsOneWidget);
    });

    testWidgets('uses initial forum name before parsed thread detail arrives', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>缓存正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: _threadDetailOverrides(repository),
          child: const MaterialApp(
            home: ThreadDetailPage(
              tid: '100',
              subject: '测试主题',
              initialForumName: '公告区',
            ),
          ),
        ),
      );

      await tester.pump();

      expect(_appBarTitleText('公告区'), findsOneWidget);
      expect(_appBarTitleText('帖子详情'), findsNothing);

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thread-post-card-p1')), findsOneWidget);
      expect(_appBarTitleText('公告区'), findsOneWidget);
    });

    testWidgets('current page button opens page menu and returns top', (
      tester,
    ) async {
      final requestedPages = <int>[];
      final repository = _FakeThreadRepository((tid, page, query) async {
        requestedPages.add(page);
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 80,
            views: 120,
            currentPage: page,
            lastPage: 20,
            previousPageUrl: page > 1
                ? 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=${page - 1}'
                : null,
            nextPageUrl: page < 20
                ? 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=${page + 1}'
                : null,
            perPage: 1,
            posts: [
              ThreadPost(
                pid: 'p$page',
                author: 'alice',
                authorId: '1',
                message: '<p>第$page页正文</p>',
                number: page,
                isFirst: page == 1,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.dragUntilVisible(
        find.byKey(const Key('thread-detail-current-page-button')),
        find.byKey(const Key('thread-detail-list')),
        const Offset(0, -260),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('thread-detail-current-page-button')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thread-detail-page-list')), findsOneWidget);
      expect(find.byKey(const Key('thread-detail-page-input')), findsNothing);
      expect(
        find.byKey(const Key('thread-detail-page-option-1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('thread-detail-page-option-3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(requestedPages, <int>[1, 3]);
      expect(_richTextContaining('第3页正文'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('thread-post-card-p3'))).dy,
        lessThan(120),
      );

      await tester.dragUntilVisible(
        find.byKey(const Key('thread-detail-current-page-button')),
        find.byKey(const Key('thread-detail-list')),
        const Offset(0, -260),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('thread-detail-current-page-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-detail-page-option-8')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(requestedPages, <int>[1, 3, 8]);
      expect(_richTextContaining('第8页正文'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('thread-post-card-p8'))).dy,
        lessThan(120),
      );

      await tester.dragUntilVisible(
        find.byKey(const Key('thread-detail-previous-page-button')),
        find.byKey(const Key('thread-detail-list')),
        const Offset(0, -260),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('thread-detail-previous-page-button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(requestedPages, <int>[1, 3, 8, 7]);
      expect(_richTextContaining('第7页正文'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('thread-post-card-p7'))).dy,
        lessThan(120),
      );
    });

    testWidgets(
      'combines author filter with order switch and pins first post in reverse view',
      (tester) async {
        final historyRecorder = _RecordingHistoryVisitRecorder();
        final repository = _FakeThreadRepository((tid, page, query) async {
          final isAuthorOnly = query['authorid'] == '1';
          final isReverse = query['ordertype'] == '1';
          return ApiSuccess(
            ThreadDetailData(
              tid: tid,
              fid: '33',
              subject: '测试主题',
              author: 'alice',
              replies: 2,
              views: 12,
              currentPage: page,
              lastPage: 1,
              reverseOrderUrl: isReverse
                  ? null
                  : 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&ordertype=1',
              onlyAuthorUrl: isAuthorOnly
                  ? null
                  : 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&authorid=1',
              desktopUrl:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=$page',
              perPage: 3,
              posts: isReverse
                  ? <ThreadPost>[
                      _post(
                        pid: 'p3',
                        author: 'alice',
                        authorId: '1',
                        number: 3,
                        message: '<p>倒序回复</p>',
                      ),
                      _post(
                        pid: 'p1',
                        author: 'alice',
                        authorId: '1',
                        number: 1,
                        isFirst: true,
                        message: '<p>主楼正文</p>',
                      ),
                    ]
                  : <ThreadPost>[
                      _post(
                        pid: 'p1',
                        author: 'alice',
                        authorId: '1',
                        number: 1,
                        isFirst: true,
                        message: '<p>主楼正文</p>',
                      ),
                      if (!isAuthorOnly)
                        _post(
                          pid: 'p2',
                          author: 'bob',
                          authorId: '2',
                          number: 2,
                          message: '<p>其他作者回复</p>',
                        ),
                    ],
            ),
          );
        });

        await tester.pumpWidget(
          _buildTestApp(repository, historyVisitRecorder: historyRecorder),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(historyRecorder.drafts, hasLength(1));

        await tester.tap(find.byKey(const Key('thread-detail-more-menu')));
        await tester.pumpAndSettle();
        expect(_popupMenuText('只看该作者'), findsOneWidget);
        expect(_popupMenuText('倒序浏览'), findsOneWidget);

        await tester.tap(_popupMenuText('只看该作者'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(repository.queryHistory.last['authorid'], '1');
        expect(repository.queryHistory.last.containsKey('ordertype'), isFalse);
        await tester.tap(find.byKey(const Key('thread-detail-more-menu')));
        await tester.pumpAndSettle();
        expect(_popupMenuText('显示全部楼层'), findsOneWidget);
        expect(_popupMenuText('倒序浏览'), findsOneWidget);

        await tester.tap(_popupMenuText('倒序浏览'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(repository.queryHistory.last['authorid'], '1');
        expect(repository.queryHistory.last['ordertype'], '1');
        expect(
          tester.getTopLeft(find.byKey(const Key('thread-post-card-p1'))).dy,
          lessThan(
            tester.getTopLeft(find.byKey(const Key('thread-post-card-p3'))).dy,
          ),
        );
        await tester.tap(find.byKey(const Key('thread-detail-more-menu')));
        await tester.pumpAndSettle();
        expect(_popupMenuText('显示全部楼层'), findsOneWidget);
        expect(_popupMenuText('正序浏览'), findsOneWidget);

        await tester.tap(_popupMenuText('正序浏览'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(repository.queryHistory.last['authorid'], '1');
        expect(repository.queryHistory.last['ordertype'], '2');
        await tester.tap(find.byKey(const Key('thread-detail-more-menu')));
        await tester.pumpAndSettle();
        expect(_popupMenuText('显示全部楼层'), findsOneWidget);
        expect(_popupMenuText('倒序浏览'), findsOneWidget);

        await tester.tap(_popupMenuText('显示全部楼层'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(repository.queryHistory.last.containsKey('authorid'), isFalse);
        expect(repository.queryHistory.last['ordertype'], '2');
        expect(historyRecorder.drafts, hasLength(1));
      },
    );

    testWidgets('selects and submits poll vote then reloads current page', (
      tester,
    ) async {
      var callCount = 0;
      final repository = _FakeThreadRepository((tid, page) async {
        callCount++;
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            typeid: '410',
            subject: '投票主题',
            author: 'alice',
            replies: 0,
            views: 12,
            currentPage: page,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                poll: ThreadPoll(
                  isMultipleChoice: false,
                  summary: '单选投票 , 投票后结果可见',
                  actionUrl:
                      'https://bbs.yamibo.com/forum.php?mod=misc&action=votepoll&tid=100',
                  formHash: 'fh_poll',
                  options: <ThreadPollOption>[
                    ThreadPollOption(
                      id: '1',
                      label: '选项A',
                      percent: callCount > 1 ? 100 : null,
                      voteCount: callCount > 1 ? 1 : null,
                    ),
                    const ThreadPollOption(id: '2', label: '选项B'),
                  ],
                ),
              ),
            ],
          ),
        );
      });
      final pollVoteRepository = _FakeThreadPollVoteRepository();
      final invalidationService = _FakeNativePageCacheInvalidationService();

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          pollVoteRepository: pollVoteRepository,
          pageCacheInvalidationService: invalidationService,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tap(find.byKey(const Key('thread-poll-option-1')));
      await tester.pump();
      final submitButton = tester.widget<FilledButton>(
        find.byKey(const Key('thread-poll-submit-button')),
      );
      expect(submitButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('thread-poll-submit-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(pollVoteRepository.called, isTrue);
      expect(pollVoteRepository.lastRequest?.tid, '100');
      expect(pollVoteRepository.lastRequest?.actionUrl, contains('votepoll'));
      expect(pollVoteRepository.lastRequest?.formHash, 'fh_poll');
      expect(pollVoteRepository.lastRequest?.optionIds, <String>['1']);
      expect(invalidationService.invalidatedThreadIds, <String>['100']);
      expect(callCount, 2);
      expect(find.text('投票成功'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('1 票'), findsOneWidget);
    });

    testWidgets('shows already-voted poll results without submit action', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            typeid: '410',
            subject: '投票主题',
            author: 'alice',
            replies: 0,
            views: 12,
            currentPage: page,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                poll: ThreadPoll(
                  isMultipleChoice: true,
                  canVote: false,
                  maxChoices: 3,
                  summary: '多选投票: ( 最多可选 3 项 ), 共有 331 人参与投票',
                  statusText: '您已经投过票，谢谢您的参与',
                  options: <ThreadPollOption>[
                    ThreadPollOption(
                      id: '1',
                      label: '两个心灵靠近的过程',
                      percent: 38.82,
                      voteCount: 276,
                      colorHex: '#E92725',
                    ),
                    ThreadPollOption(
                      id: '2',
                      label: '背德扭曲神人爆爆爆',
                      percent: 11.25,
                      voteCount: 80,
                      colorHex: '#F27B21',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      });
      final pollVoteRepository = _FakeThreadPollVoteRepository();

      await tester.pumpWidget(
        _buildTestApp(repository, pollVoteRepository: pollVoteRepository),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('两个心灵靠近的过程'), findsOneWidget);
      expect(find.text('38.82%'), findsOneWidget);
      expect(find.text('276 票'), findsOneWidget);
      expect(find.text('您已经投过票，谢谢您的参与'), findsOneWidget);
      expect(find.byKey(const Key('thread-poll-submit-button')), findsNothing);

      await tester.tap(find.byKey(const Key('thread-poll-option-1')));
      await tester.pump();

      expect(pollVoteRepository.called, isFalse);
      expect(find.byIcon(Icons.check_box), findsNothing);
      expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
    });

    testWidgets('opens same-domain tag link from post body natively', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '30',
            subject: '漫画主题',
            author: 'alice',
            replies: 0,
            views: 12,
            currentPage: page,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message:
                    '<a href="https://bbs.yamibo.com/misc.php?mod=tag&id=20674">目录</a>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });
      final tagRepository = _FakeYamiboTagThreadPageRepository();

      await tester.pumpWidget(
        _buildTestApp(repository, tagThreadPageRepository: tagRepository),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tapAt(
        tester.getTopLeft(_richTextContaining('目录')) + const Offset(4, 8),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(tagRepository.requestedUrls.single, contains('id=20674'));
      expect(find.byKey(const Key('yamibo-tag-thread-page')), findsOneWidget);
    });

    testWidgets('opens same-domain thread link from post body natively', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '30',
            subject: tid == '572514' ? '跳转后的帖子' : '漫画主题',
            author: 'alice',
            replies: 0,
            views: 12,
            currentPage: page,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p$tid',
                author: 'alice',
                authorId: '1',
                message: tid == '572514'
                    ? '<p>新帖子正文</p>'
                    : '<a href="https://bbs.yamibo.com/thread-572514-1-1.html">00</a>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tapAt(
        tester.getTopLeft(_richTextContaining('00')) + const Offset(4, 8),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('跳转后的帖子'), findsWidgets);
      expect(_richTextContaining('新帖子正文'), findsOneWidget);
    });

    testWidgets('opens viewthread pid link at target page natively', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '55',
            subject: tid == '572057' ? '目标帖子' : '来源帖子',
            author: 'alice',
            replies: 3,
            views: 12,
            currentPage: page,
            lastPage: 3,
            perPage: 20,
            posts: tid == '572057' && page == 3
                ? [
                    for (var index = 0; index < 18; index++)
                      ThreadPost(
                        pid: index == 17 ? '41560047' : 'target-$index',
                        author: 'target',
                        authorId: '2',
                        message: index == 17
                            ? '<p>目标楼层正文</p>'
                            : '<p>占位回复 $index</p>',
                        number: index + 1,
                        isFirst: index == 0,
                        dateline: 'today',
                      ),
                  ]
                : [
                    ThreadPost(
                      pid: 'source',
                      author: 'alice',
                      authorId: '1',
                      message:
                          '<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&tid=572057&page=3&extra=#pid41560047">跳到楼层</a>',
                      number: 1,
                      isFirst: true,
                      dateline: 'today',
                    ),
                  ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tapAt(
        tester.getTopLeft(_richTextContaining('跳到楼层')) + const Offset(4, 8),
      );
      await tester.pumpAndSettle();

      expect(_appBarTitleText('目标帖子'), findsNothing);
      expect(
        find.byKey(const Key('thread-post-card-41560047')),
        findsOneWidget,
      );
      expect(_richTextContaining('目标楼层正文'), findsOneWidget);
      final listTop = tester.getTopLeft(
        find.byKey(const Key('thread-detail-list')),
      );
      final targetTop = tester.getTopLeft(
        find.byKey(const Key('thread-post-card-41560047')),
      );
      expect(
        targetTop.dy,
        closeTo(listTop.dy + 10, 28),
        reason: '目标楼层应贴近 AppBar 下方的列表顶部，而不是落在屏幕中部',
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('thread-detail-list')),
          matching: find.byType(Scrollable),
        ),
      );
      for (var attempt = 0; attempt < 4; attempt++) {
        scrollable.position.jumpTo(scrollable.position.minScrollExtent);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final firstPost = find.byKey(const Key('thread-post-card-target-0'));
      expect(firstPost, findsOneWidget);
      expect(tester.getTopLeft(firstPost).dy, closeTo(listTop.dy + 10, 1));
    });

    testWidgets(
      'locates the second post after an exceptionally long first post',
      (tester) async {
        final historyRecorder = _RecordingHistoryVisitRecorder();
        tester.view.physicalSize = const Size(390, 260);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final longFirstPost = [
          for (var index = 0; index < 120; index++)
            '<p>首楼中的长篇简介和目录内容 $index</p>',
        ].join();
        final repository = _FakeThreadRepository((tid, page) async {
          return ApiSuccess(
            ThreadDetailData(
              tid: tid,
              fid: '55',
              subject: '超长首楼定位测试',
              author: 'author',
              replies: 1,
              views: 12,
              currentPage: 1,
              lastPage: 1,
              perPage: 20,
              posts: <ThreadPost>[
                ThreadPost(
                  pid: 'first-post',
                  author: 'author',
                  authorId: '1',
                  message: longFirstPost,
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
                ThreadPost(
                  pid: 'target-second-post',
                  author: 'author',
                  authorId: '1',
                  message: '<p>第一话 姐姐的日记</p>',
                  number: 2,
                  isFirst: false,
                  dateline: 'today',
                ),
              ],
            ),
          );
        });

        await tester.pumpWidget(
          _buildTestApp(
            repository,
            historyVisitRecorder: historyRecorder,
            home: const ThreadDetailPage(
              tid: '556943',
              initialPage: 1,
              targetPid: 'target-second-post',
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        final listTop = tester.getTopLeft(
          find.byKey(const Key('thread-detail-list')),
        );
        final targetTop = tester.getTopLeft(
          find.byKey(const Key('thread-post-card-target-second-post')),
        );
        expect(targetTop.dy, closeTo(listTop.dy + 10, 28));
        expect(_richTextContaining('第一话 姐姐的日记'), findsOneWidget);
        expect(historyRecorder.drafts, hasLength(1));
        expect(historyRecorder.drafts.single.target.id, '556943');
      },
    );

    testWidgets(
      'keeps target anchored when the first post grows asynchronously',
      (tester) async {
        tester.view.physicalSize = const Size(390, 260);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final converter = _ControlledExpandingTextConverter();
        final preferencesRepository = _FakeForumHtmlReaderPreferencesRepository(
          ForumHtmlReaderPreferences.defaults().copyWith(
            conversionMode: TextConversionMode.toSimplified,
          ),
        );
        final repository = _FakeThreadRepository((tid, page) async {
          return ApiSuccess(
            ThreadDetailData(
              tid: tid,
              fid: '55',
              subject: '异步首楼定位测试',
              author: 'author',
              replies: 1,
              views: 12,
              currentPage: 1,
              lastPage: 1,
              perPage: 20,
              posts: <ThreadPost>[
                ThreadPost(
                  pid: 'async-first-post',
                  author: 'author',
                  authorId: '1',
                  message: '<p>短首楼樣</p>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
                ThreadPost(
                  pid: 'async-target-post',
                  author: 'author',
                  authorId: '1',
                  message: '<p>第一话 姐姐的日记</p>',
                  number: 2,
                  isFirst: false,
                  dateline: 'today',
                ),
              ],
            ),
          );
        });

        await tester.pumpWidget(
          _buildTestApp(
            repository,
            forumHtmlReaderPreferencesRepository: preferencesRepository,
            textConverterFactory: (mode) =>
                mode == TextConversionMode.toSimplified
                ? converter
                : _FakeTextConverter(mode),
            home: const ThreadDetailPage(
              tid: '556943',
              initialPage: 1,
              targetPid: 'async-target-post',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byKey(const Key('thread-target-post-positioning-indicator')),
          findsNothing,
        );
        final listFinder = find.byKey(const Key('thread-detail-list'));
        final targetFinder = find.byKey(
          const Key('thread-post-card-async-target-post'),
        );
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: listFinder, matching: find.byType(Scrollable)),
        );
        double targetTop() => tester.getTopLeft(targetFinder).dy;
        double listTop() => tester.getTopLeft(listFinder).dy;
        expect(targetTop(), closeTo(listTop() + 10, 1));
        expect(scrollable.position.pixels, closeTo(0, 0.01));
        converter.release();
        await tester.pump();
        for (var index = 0; index < 10; index++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(targetTop(), closeTo(listTop() + 10, 1));
          expect(scrollable.position.pixels, closeTo(0, 0.01));
          expect(
            find.byKey(const Key('thread-target-post-positioning-indicator')),
            findsNothing,
          );
        }

        final firstPostFinder = find.byKey(
          const Key('thread-post-card-async-first-post'),
        );
        scrollable.position.jumpTo(scrollable.position.minScrollExtent);
        await tester.pumpAndSettle();
        expect(firstPostFinder, findsOneWidget);
        expect(
          tester.getTopLeft(firstPostFinder).dy,
          closeTo(listTop() + 10, 1),
        );
      },
    );

    testWidgets('locates findpost link before opening native thread page', (
      tester,
    ) async {
      final historyRecorder = _RecordingHistoryVisitRecorder();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '55',
            subject: tid == '572057' ? '目标帖子' : '来源帖子',
            author: 'alice',
            replies: 2,
            views: 12,
            currentPage: page,
            lastPage: 2,
            perPage: 20,
            posts: [
              if (tid == '572057' && page == 2)
                ThreadPost(
                  pid: '41554030',
                  author: 'target',
                  authorId: '2',
                  message: '<p>定位后的楼层</p>',
                  number: 2,
                  isFirst: false,
                  dateline: 'today',
                )
              else
                ThreadPost(
                  pid: 'source',
                  author: 'alice',
                  authorId: '1',
                  message:
                      '<a href="https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=572057&pid=41554030&fromuid=420637">findpost</a>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
            ],
          ),
        );
      });
      final locator = _FakeThreadPostLocator(
        const ThreadPostLocation(
          tid: '572057',
          pid: '41554030',
          page: 2,
          url:
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=572057&page=2#pid41554030',
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          threadPostLocator: locator,
          historyVisitRecorder: historyRecorder,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(historyRecorder.drafts, hasLength(1));
      expect(historyRecorder.drafts.single.target.id, '100');

      await tester.tapAt(
        tester.getTopLeft(_richTextContaining('findpost')) + const Offset(4, 8),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(locator.lastTid, '572057');
      expect(locator.lastPid, '41554030');
      expect(locator.lastSourceUri?.query, contains('goto=findpost'));
      expect(
        find.byKey(const Key('thread-post-card-41554030')),
        findsOneWidget,
      );
      expect(_richTextContaining('定位后的楼层'), findsOneWidget);
      expect(historyRecorder.drafts, hasLength(2));
      expect(historyRecorder.drafts.last.target.id, '572057');
    });

    testWidgets('keeps large thread pages lazy built for smoother rendering', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '55',
            subject: '大文本帖子',
            author: 'alice',
            replies: 80,
            views: 12,
            currentPage: 1,
            lastPage: 1,
            perPage: 80,
            posts: [
              for (var index = 0; index < 80; index++)
                ThreadPost(
                  pid: 'bulk-$index',
                  author: 'author',
                  authorId: '$index',
                  message: '<p>正文 $index ${'长文本 '.padRight(260, 'x')}</p>',
                  number: index + 1,
                  isFirst: index == 0,
                  dateline: 'today',
                ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final list = tester.widget<ListView>(
        find.byKey(const Key('thread-detail-list')),
      );
      expect(list.scrollCacheExtent, const ScrollCacheExtent.pixels(900));
      expect(find.byKey(const Key('thread-post-card-bulk-0')), findsOneWidget);
      expect(find.byKey(const Key('thread-post-card-bulk-79')), findsNothing);
    });

    testWidgets('renders long text post as one HTML-first body', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final longParagraph = List.filled(520, '长正文片段').join();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '55',
            subject: '长正文帖子',
            author: 'alice',
            replies: 0,
            views: 12,
            currentPage: 1,
            lastPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'long-1',
                author: 'author',
                authorId: '1',
                message: '<p>$longParagraph</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('thread-post-card-long-1')), findsOneWidget);
      expect(find.byKey(const Key('thread-post-body-long-1')), findsOneWidget);
      expect(find.byKey(const Key('thread-post-body-long-1-0')), findsNothing);
      expect(find.byType(ThreadPostHtmlBody), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const Key('thread-detail-list')),
          matching: find.byType(SelectionArea),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byType(Scrollable).first,
          matching: find.byType(SelectionArea),
        ),
        findsNothing,
      );
      final bodyRichTexts = tester.widgetList<RichText>(
        find.descendant(
          of: find.byKey(const Key('thread-post-body-long-1')),
          matching: find.byType(RichText),
        ),
      );
      expect(bodyRichTexts, isNotEmpty);
      expect(
        bodyRichTexts.every((text) => text.selectionRegistrar == null),
        isTrue,
      );
    });

    testWidgets('uses one HTML-first body entry for image dense posts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final imageHtml = List.generate(
        7,
        (index) =>
            '<img src="static/image/common/none.gif" file="data/attachment/forum/page-$index.jpg" />',
      ).join();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '55',
            subject: '多图帖子',
            author: 'alice',
            replies: 0,
            views: 12,
            currentPage: 1,
            lastPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'image-1',
                author: 'author',
                authorId: '1',
                message: '<p>开头</p>$imageHtml<p>结尾</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('thread-post-card-image-1')), findsOneWidget);
      expect(find.byKey(const Key('thread-post-body-image-1')), findsOneWidget);
      expect(find.byKey(const Key('thread-post-body-image-1-0')), findsNothing);
      expect(find.byKey(const Key('thread-post-body-image-1-6')), findsNothing);
      expect(
        find.byKey(
          const Key('thread-post-html-first-readable-image-image-1-0'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('long pressing post body opens copy actions and copy page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final copiedTexts = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = Map<String, dynamic>.from(call.arguments as Map);
            copiedTexts.add(data['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      final longParagraph = List.filled(360, '长正文片段').join();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '55',
            subject: '复制测试',
            author: 'alice',
            replies: 1,
            views: 12,
            currentPage: 1,
            lastPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'copy-1',
                author: 'author',
                authorId: '1',
                message:
                    '<p>第一段 <a href="thread-1-1-1.html">链接文本</a> $longParagraph</p>'
                    '<div class="quote"><blockquote><b>作者</b>: 引用正文</blockquote></div>'
                    '<img file="data/attachment/forum/page.jpg" />'
                    '<p>尾段 <img src="static/image/smiley/comcom/2.gif" alt="[笑]"></p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
              ThreadPost(
                pid: 'copy-2',
                author: 'other',
                authorId: '2',
                message: '<p>其它楼正文</p>',
                number: 2,
                isFirst: false,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('thread-post-body-copy-1')), findsOneWidget);
      expect(find.byKey(const Key('thread-post-body-copy-1-0')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('thread-post-body-copy-1')),
          matching: find.byType(SelectionArea),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('thread-detail-list')),
          matching: find.byType(SelectionArea),
        ),
        findsNothing,
      );
      final headerRichTexts = tester.widgetList<RichText>(
        find.descendant(
          of: find.byKey(const Key('thread-post-card-copy-1')),
          matching: find.byType(RichText),
        ),
      );
      expect(headerRichTexts, isNotEmpty);
      expect(
        headerRichTexts.every((text) => text.selectionRegistrar == null),
        isTrue,
      );
      expect(find.byKey(const Key('thread-post-card-copy-1')), findsOneWidget);

      await _longPressVisibleTop(
        tester,
        find.byKey(const Key('thread-post-body-copy-1')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thread-post-action-sheet')), findsOneWidget);
      expect(find.text('回复'), findsOneWidget);
      expect(find.text('选择复制'), findsOneWidget);
      expect(find.text('全部复制'), findsOneWidget);

      await _tapPostActionSheetItem(
        tester,
        const Key('thread-post-copy-all-action'),
      );
      await tester.pumpAndSettle();

      expect(copiedTexts.single, contains('第一段链接文本'));
      expect(copiedTexts.single, contains('作者: 引用正文'));
      expect(copiedTexts.single, contains('尾段[笑]'));
      expect(copiedTexts.single, isNot(contains('page.jpg')));
      expect(find.text('1# 正文已复制'), findsOneWidget);

      await _longPressVisibleTop(
        tester,
        find.byKey(const Key('thread-post-body-copy-1')),
      );
      await tester.pumpAndSettle();
      await _tapPostActionSheetItem(
        tester,
        const Key('thread-post-select-copy-action'),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-post-html-selection-copy-page')),
        findsOneWidget,
      );
      expect(find.text('选择复制'), findsOneWidget);
      expect(
        find.byKey(const Key('thread-post-html-selection-copy-body-copy-1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const Key('thread-post-html-selection-copy-body-copy-1'),
          ),
          matching: find.byType(SelectionArea),
        ),
        findsNothing,
      );
      final copyPageRichTexts = tester.widgetList<RichText>(
        find.descendant(
          of: find.byKey(
            const Key('thread-post-html-selection-copy-body-copy-1'),
          ),
          matching: find.byType(RichText),
        ),
      );
      expect(
        copyPageRichTexts.any((text) => text.selectionRegistrar != null),
        isTrue,
      );
    });

    testWidgets('uses current thread page as post image referer', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '30',
            subject: '带图主题',
            author: 'alice',
            replies: 0,
            views: 12,
            currentPage: page,
            perPage: 20,
            desktopUrl:
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&page=$page',
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message:
                    '<img src="static/image/common/none.gif" file="data/attachment/forum/page-1.jpg" />',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();

      final image = tester.widget<CachedLibraryImage>(
        find.descendant(
          of: find.byKey(
            const Key('thread-post-html-first-readable-image-p1-0'),
          ),
          matching: find.byType(CachedLibraryImage),
        ),
      );
      final request = image.request;
      expect(request, isNotNull);
      expect(
        request!.sourceUrl,
        'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
      );
      expect(image.headerBuilder, isNotNull);
      final headers = await image.headerBuilder!.buildHeaders(
        request.sourceUrl,
      );
      expect(
        headers['Referer'],
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
      );
      expect(headers['User-Agent'], contains('Chrome'));
      expect(headers['Accept'], contains('image/'));
    });

    testWidgets('opens native rate sheet and submits post rating', (
      tester,
    ) async {
      var loadCount = 0;
      final repository = _FakeThreadRepository((tid, page) async {
        loadCount++;
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                rateUrl:
                    'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=100&pid=p1',
              ),
            ],
          ),
        );
      });
      final rateRepository = _FakeThreadPostRateRepository();
      final invalidationService = _FakeNativePageCacheInvalidationService();

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          postRateRepository: rateRepository,
          pageCacheInvalidationService: invalidationService,
        ),
      );
      await tester.pumpAndSettle();

      await _openPostAction(
        tester,
        bodyKey: const Key('thread-post-body-p1'),
        actionKey: const Key('thread-post-rate-action'),
      );
      await tester.pumpAndSettle();

      expect(rateRepository.loadedUrl, contains('action=rate'));
      expect(find.byKey(const Key('thread-post-rate-sheet')), findsOneWidget);
      expect(find.text('范围 0~5，今日剩余 10'), findsOneWidget);

      await tester.tap(find.byKey(const Key('thread-post-rate-reason-我很赞同')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('thread-post-rate-submit-button')));
      await tester.pumpAndSettle();

      expect(rateRepository.lastDraft?.form.pid, 'p1');
      expect(rateRepository.lastDraft?.form.referer, contains('#pidp1'));
      expect(rateRepository.lastDraft?.score, 5);
      expect(rateRepository.lastDraft?.reason, '我很赞同');
      expect(rateRepository.lastDraft?.notifyAuthor, isFalse);
      expect(invalidationService.invalidatedThreadIds, <String>['100']);
      expect(loadCount, 2);
      expect(find.text('评分成功'), findsOneWidget);
    });

    testWidgets('opens native comment sheet and submits post comment', (
      tester,
    ) async {
      var loadCount = 0;
      final repository = _FakeThreadRepository((tid, page) async {
        loadCount++;
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                commentUrl:
                    'https://bbs.yamibo.com/forum.php?mod=misc&action=comment&tid=100&pid=p1',
              ),
            ],
          ),
        );
      });
      final commentRepository = _FakeThreadPostCommentRepository();
      final invalidationService = _FakeNativePageCacheInvalidationService();

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          postCommentRepository: commentRepository,
          pageCacheInvalidationService: invalidationService,
        ),
      );
      await tester.pumpAndSettle();

      await _openPostAction(
        tester,
        bodyKey: const Key('thread-post-body-p1'),
        actionKey: const Key('thread-post-comment-action'),
      );
      await tester.pumpAndSettle();

      expect(commentRepository.loadedUrl, contains('action=comment'));
      expect(
        find.byKey(const Key('thread-post-comment-sheet')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('thread-post-comment-message-input')),
        '这是测试点评',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('thread-post-comment-submit-button')),
      );
      await tester.pumpAndSettle();

      expect(commentRepository.lastDraft?.form.pid, 'p1');
      expect(commentRepository.lastDraft?.message, '这是测试点评');
      expect(invalidationService.invalidatedThreadIds, <String>['100']);
      expect(loadCount, 2);
      expect(find.text('点评成功'), findsOneWidget);
    });

    testWidgets('hides comment action when post has no comment url', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 1,
            views: 1,
            currentPage: 2,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p2',
                author: 'bob',
                authorId: '2',
                message: '<p>第二楼</p>',
                number: 2,
                isFirst: false,
                dateline: 'today',
              ),
            ],
          ),
        );
      });
      final commentRepository = _FakeThreadPostCommentRepository();

      await tester.pumpWidget(
        _buildTestApp(repository, postCommentRepository: commentRepository),
      );
      await tester.pumpAndSettle();

      await _longPressVisibleTop(
        tester,
        find.byKey(const Key('thread-post-body-p2')),
      );
      await tester.pumpAndSettle();

      final actionSheet = find.byKey(const Key('thread-post-action-sheet'));
      expect(actionSheet, findsOneWidget);
      expect(
        find.descendant(of: actionSheet, matching: find.text('点评')),
        findsNothing,
      );
      expect(
        find.descendant(of: actionSheet, matching: find.text('回复')),
        findsOneWidget,
      );
      expect(commentRepository.loadedSeed, isNull);
      expect(commentRepository.loadedUrl, isNull);
    });

    testWidgets('diagnostic post actions do not expose HTML-first comparison', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          _threadDetailData(
            tid: tid,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>对照正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(repository, diagnosticModeEnabled: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await _longPressVisibleTop(
        tester,
        find.byKey(const Key('thread-post-body-p1')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-post-html-first-compare-action')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('thread-post-select-copy-action')),
        findsOneWidget,
      );
    });

    testWidgets('renders comic forum posts without eager shelf parsing', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '30',
            typeid: '398',
            subject: '【测试汉化组】第1话',
            author: 'alice',
            replies: 0,
            views: 12,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message:
                    '<p>漫画正文</p><img src="https://img.test/1.jpg"/><img src="https://img.test/%E3.jpg"/><a href="thread-100-1-1.html">1</a><a href="thread-101-1-1.html">2</a>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('thread-post-card-p1')), findsOneWidget);
      expect(
        find.byKey(const Key('thread-post-html-first-body-p1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('comic-add-to-shelf-button')), findsNothing);
      expect(find.byKey(const Key('comic-in-shelf-button')), findsNothing);
      expect(find.text('漫画 · 韩国漫画'), findsNothing);
      expect(find.textContaining('漫画候选（评分'), findsNothing);
    });

    testWidgets('hides local shelf entry for fid 49 novel first post', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '49',
            typeid: '293',
            subject: '测试小说帖',
            author: 'alice',
            replies: 0,
            views: 12,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>第1章 开始</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      final novelRepository = _FakeNovelRepository();

      await tester.pumpWidget(
        _buildTestApp(repository, novelRepository: novelRepository),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('小说 · 原创'), findsNothing);
      expect(find.byKey(const Key('comic-add-to-shelf-button')), findsNothing);
      expect(find.byKey(const Key('comic-in-shelf-button')), findsNothing);
      expect(novelRepository.upsertCalled, isFalse);
      expect(novelRepository.refreshCalled, isFalse);
    });

    testWidgets(
      'keeps comic second-floor content as normal post detail content',
      (tester) async {
        final repository = _FakeThreadRepository((tid, page) async {
          return ApiSuccess(
            ThreadDetailData(
              tid: tid,
              fid: '30',
              typeid: '398',
              subject: '【测试汉化组】第1话',
              author: 'alice',
              replies: 1,
              views: 12,
              currentPage: 1,
              perPage: 20,
              posts: [
                ThreadPost(
                  pid: 'p1',
                  author: 'alice',
                  authorId: '1',
                  message: '<p>前言</p><img src="https://img.test/cover.jpg"/>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
                ThreadPost(
                  pid: 'p2',
                  author: 'alice',
                  authorId: '1',
                  message:
                      '<img src="https://img.test/page-1.jpg"/><img src="https://img.test/page-2.jpg"/>',
                  number: 2,
                  isFirst: false,
                  dateline: 'today',
                ),
              ],
            ),
          );
        });

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(find.byKey(const Key('thread-post-card-p1')), findsOneWidget);
        expect(
          find.byKey(const Key('thread-post-html-first-body-p1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('comic-add-to-shelf-button')),
          findsNothing,
        );
      },
    );

    testWidgets('hides search-in-forum action on thread detail page', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '30',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-detail-search-button')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('thread-detail-favorite-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('thread-detail-appbar-reply-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('thread-detail-more-menu')), findsOneWidget);
    });

    testWidgets('opens compact display settings from more menu', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thread-detail-more-menu')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('thread-detail-display-settings-menu-item')),
        findsOneWidget,
      );

      await tester.tap(find.text('显示设置'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-detail-display-settings-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-html-reader-conversion-mode-control')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-html-reader-conversion-none')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-html-reader-conversion-simplified')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-html-reader-conversion-traditional')),
        findsOneWidget,
      );
      expect(find.text('字号'), findsOneWidget);
      expect(find.text('间隔'), findsOneWidget);
      expect(
        find.byKey(const Key('forum-html-reader-font-scale-slider')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-html-reader-line-height-slider')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-html-reader-paragraph-spacing-slider')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('forum-html-reader-preserve-font-size-switch')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('forum-html-reader-preserve-color-switch')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('forum-html-reader-preserve-background-switch')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('forum-html-reader-reset-button')),
        findsNothing,
      );
    });

    testWidgets('display settings conversion only updates post body text', (
      tester,
    ) async {
      final preferencesRepository = _FakeForumHtmlReaderPreferencesRepository(
        ForumHtmlReaderPreferences.defaults(),
      );
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '測試主题',
            author: 'alice樣',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice樣',
                authorId: '1',
                message: '<p>正文樣本</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          forumHtmlReaderPreferencesRepository: preferencesRepository,
          textConverterFactory: _FakeTextConverter.new,
        ),
      );
      await tester.pumpAndSettle();

      expect(_richTextContaining('正文樣本'), findsOneWidget);
      expect(find.textContaining('alice樣'), findsOneWidget);

      await tester.tap(find.byKey(const Key('thread-detail-more-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示设置'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('forum-html-reader-conversion-simplified')),
      );
      await tester.pumpAndSettle();

      expect(
        preferencesRepository.current.conversionMode,
        TextConversionMode.toSimplified,
      );
      expect(_richTextContaining('正文样本'), findsOneWidget);
      expect(_richTextContaining('正文樣本'), findsNothing);
      expect(find.textContaining('alice樣'), findsOneWidget);
      expect(find.textContaining('alice样'), findsNothing);
    });

    testWidgets('opens user profile from post author name', (tester) async {
      final webViewDriver = _FakeForumWebViewDriver();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '509957',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          forumWebViewDriverFactory: () => webViewDriver,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('alice').first);
      await tester.pumpAndSettle();

      expect(find.byType(ForumWebViewPage), findsOneWidget);
      expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
      expect(
        webViewDriver.bootstrapConfig?.initialUri.toString(),
        'https://bbs.yamibo.com/home.php?mod=space&uid=509957&mobile=2',
      );
      expect(webViewDriver.loadedUris, <Uri>[
        Uri.parse(
          'https://bbs.yamibo.com/home.php?mod=space&uid=509957&mobile=2',
        ),
      ]);
    });

    testWidgets('opens user profile from post author avatar', (tester) async {
      final webViewDriver = _FakeForumWebViewDriver();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '509957',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          forumWebViewDriverFactory: () => webViewDriver,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thread-author-avatar-p1')));
      await tester.pumpAndSettle();

      expect(find.byType(ForumWebViewPage), findsOneWidget);
      expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
      expect(
        webViewDriver.bootstrapConfig?.initialUri.toString(),
        'https://bbs.yamibo.com/home.php?mod=space&uid=509957&mobile=2',
      );
    });

    testWidgets('opens user profile from comment author name', (tester) async {
      final webViewDriver = _FakeForumWebViewDriver();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                comments: const <ThreadPostCommentEntry>[
                  ThreadPostCommentEntry(
                    author: 'commenter',
                    authorId: '777',
                    authorUrl:
                        'https://bbs.yamibo.com/home.php?mod=space&uid=777&mobile=2',
                    avatarUrl:
                        'https://bbs.yamibo.com/uc_server/data/avatar/000/00/07/77_avatar_small.jpg',
                    message: '点评内容',
                    dateline: 'today',
                  ),
                ],
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          forumWebViewDriverFactory: () => webViewDriver,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thread-comment-author-name-777')));
      await tester.pumpAndSettle();

      expect(find.byType(ForumWebViewPage), findsOneWidget);
      expect(
        webViewDriver.bootstrapConfig?.initialUri.toString(),
        'https://bbs.yamibo.com/home.php?mod=space&uid=777&mobile=2',
      );
      expect(webViewDriver.loadedUris, <Uri>[
        Uri.parse('https://bbs.yamibo.com/home.php?mod=space&uid=777&mobile=2'),
      ]);
    });

    testWidgets('opens user profile from comment author avatar', (
      tester,
    ) async {
      final webViewDriver = _FakeForumWebViewDriver();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                comments: const <ThreadPostCommentEntry>[
                  ThreadPostCommentEntry(
                    author: 'commenter',
                    authorId: '778',
                    avatarUrl:
                        'https://bbs.yamibo.com/uc_server/data/avatar/000/00/07/78_avatar_small.jpg',
                    message: '点评内容',
                    dateline: 'today',
                  ),
                ],
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          forumWebViewDriverFactory: () => webViewDriver,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('thread-comment-author-avatar-778')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ForumWebViewPage), findsOneWidget);
      expect(
        webViewDriver.bootstrapConfig?.initialUri.toString(),
        'https://bbs.yamibo.com/home.php?mod=space&uid=778&mobile=2',
      );
    });

    testWidgets('opens comment profile from author url uid when id is empty', (
      tester,
    ) async {
      final webViewDriver = _FakeForumWebViewDriver();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                comments: const <ThreadPostCommentEntry>[
                  ThreadPostCommentEntry(
                    author: 'url-user',
                    authorId: '',
                    authorUrl: 'home.php?mod=space&uid=888&mobile=2',
                    message: '点评内容',
                    dateline: 'today',
                  ),
                ],
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          forumWebViewDriverFactory: () => webViewDriver,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('url-user'));
      await tester.pumpAndSettle();

      expect(find.byType(ForumWebViewPage), findsOneWidget);
      expect(
        webViewDriver.bootstrapConfig?.initialUri.toString(),
        'https://bbs.yamibo.com/home.php?mod=space&uid=888&mobile=2',
      );
    });

    testWidgets('shows snackbar when comment author uid is missing', (
      tester,
    ) async {
      final webViewDriver = _FakeForumWebViewDriver();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                comments: const <ThreadPostCommentEntry>[
                  ThreadPostCommentEntry(
                    author: 'missing-user',
                    message: '点评内容',
                    dateline: 'today',
                  ),
                ],
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          forumWebViewDriverFactory: () => webViewDriver,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('missing-user'));
      await tester.pump();

      expect(find.text('用户 UID 缺失'), findsOneWidget);
      expect(find.byType(ForumWebViewPage), findsNothing);
      expect(webViewDriver.loadedUris, isEmpty);
    });

    testWidgets('default comment avatar uses local noavatar asset', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                comments: const <ThreadPostCommentEntry>[
                  ThreadPostCommentEntry(
                    author: 'commenter',
                    authorId: '779',
                    avatarUrl:
                        'https://bbs.yamibo.com/uc_server/data/avatar/noavatar.svg',
                    message: '点评内容',
                    dateline: 'today',
                  ),
                ],
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('thread-comment-author-avatar-779')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName ==
                    forumDefaultAvatarAsset,
          ),
        ),
      );
      expect((image.image as AssetImage).assetName, forumDefaultAvatarAsset);
    });

    testWidgets('comment avatar uses avatar cache request baseline', (
      tester,
    ) async {
      final cacheService = _RecordingImageCacheService();
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                comments: const <ThreadPostCommentEntry>[
                  ThreadPostCommentEntry(
                    author: 'commenter',
                    authorId: '780',
                    avatarUrl:
                        'https://bbs.yamibo.com/uc_server/data/avatar/000/00/07/80_avatar_small.jpg',
                    message: '点评内容',
                    dateline: 'today',
                  ),
                ],
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(
        _buildTestApp(repository, imageCacheService: cacheService),
      );
      await tester.pump();
      await tester.pump();

      final cachedAvatar = tester.widget<CachedLibraryImage>(
        find.descendant(
          of: find.byKey(const Key('thread-comment-author-avatar-780')),
          matching: find.byType(CachedLibraryImage),
        ),
      );

      expect(cachedAvatar.request?.role, ImageCacheRole.avatar);
      expect(cachedAvatar.request?.ownerType, ImageCacheOwnerType.thread);
      expect(cachedAvatar.request?.ownerId, '780');
      expect(
        cachedAvatar.request?.sourceUrl,
        'https://bbs.yamibo.com/uc_server/data/avatar/000/00/07/80_avatar_small.jpg',
      );
      expect(
        cacheService.requests.where(
          (request) => request.role == ImageCacheRole.avatar,
        ),
        isNotEmpty,
      );
    });

    testWidgets('favorites thread from app bar action', (tester) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });
      final favoriteActionService = _FakeThreadFavoriteActionService();

      await tester.pumpWidget(
        _buildTestApp(repository, favoriteActionService: favoriteActionService),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thread-detail-favorite-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(favoriteActionService.called, isTrue);
      expect(favoriteActionService.lastTid, '100');
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.text('收藏成功'), findsOneWidget);
    });

    testWidgets('opens reply composer and submits reply via shared composer', (
      tester,
    ) async {
      final repository = _FakeThreadRepository((tid, page) async {
        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '33',
            subject: '测试主题',
            author: 'alice',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: [
              ThreadPost(
                pid: 'p1',
                author: 'alice',
                authorId: '1',
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
              ),
            ],
          ),
        );
      });
      final replyRepo = _FakeReplyRepository();
      final invalidationService = _FakeNativePageCacheInvalidationService();

      await tester.pumpWidget(
        _buildTestApp(
          repository,
          replyRepository: replyRepo,
          pageCacheInvalidationService: invalidationService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thread-reply-submit-button')), findsNothing);
      expect(find.byKey(const Key('thread-reply-input')), findsNothing);

      await tester.tap(
        find.byKey(const Key('thread-detail-appbar-reply-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reply-composer-quill-editor')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('reply-composer-source-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('reply-composer-message-input')),
        '这是测试回复',
      );
      await tester.pump();
      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('reply-composer-send-button')),
      );
      expect(sendButton.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('reply-composer-send-button')));
      await tester.pumpAndSettle();

      expect(replyRepo.called, isTrue);
      expect(replyRepo.lastDraft?.message, '这是测试回复');
      expect(invalidationService.invalidatedThreadIds, <String>['100']);
      expect(find.text('回复发布成功'), findsOneWidget);
    });
  });
}

Widget _buildTestApp(
  ThreadRepository repository, {
  ReplyRepository? replyRepository,
  NovelRepository? novelRepository,
  ThreadFavoriteActionService? favoriteActionService,
  ThreadPostRateRepository? postRateRepository,
  ThreadPostCommentRepository? postCommentRepository,
  ThreadPollVoteRepository? pollVoteRepository,
  YamiboTagThreadPageRepository? tagThreadPageRepository,
  ThreadPostLocator? threadPostLocator,
  NativePageCacheInvalidationService? pageCacheInvalidationService,
  ImageCacheService? imageCacheService,
  ForumImagePrecacheService? forumImagePrecacheService,
  ForumWebViewDriverFactory? forumWebViewDriverFactory,
  ForumHtmlReaderPreferencesRepository? forumHtmlReaderPreferencesRepository,
  TextConverter Function(TextConversionMode mode)? textConverterFactory,
  bool diagnosticModeEnabled = false,
  HistoryVisitRecorder? historyVisitRecorder,
  HistoryDiagnosticRecorder? historyDiagnosticRecorder,
  Widget? home,
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: _threadDetailOverrides(
      repository,
      replyRepository: replyRepository,
      novelRepository: novelRepository,
      favoriteActionService: favoriteActionService,
      postRateRepository: postRateRepository,
      postCommentRepository: postCommentRepository,
      pollVoteRepository: pollVoteRepository,
      tagThreadPageRepository: tagThreadPageRepository,
      threadPostLocator: threadPostLocator,
      pageCacheInvalidationService: pageCacheInvalidationService,
      imageCacheService: imageCacheService,
      forumImagePrecacheService: forumImagePrecacheService,
      forumWebViewDriverFactory: forumWebViewDriverFactory,
      forumHtmlReaderPreferencesRepository:
          forumHtmlReaderPreferencesRepository,
      textConverterFactory: textConverterFactory,
      diagnosticModeEnabled: diagnosticModeEnabled,
      historyVisitRecorder: historyVisitRecorder,
      historyDiagnosticRecorder: historyDiagnosticRecorder,
    ),
    child: MaterialApp(
      theme: theme,
      home: home ?? const ThreadDetailPage(tid: '100', subject: '测试主题'),
    ),
  );
}

List<riverpod_misc.Override> _threadDetailOverrides(
  ThreadRepository repository, {
  ReplyRepository? replyRepository,
  NovelRepository? novelRepository,
  ThreadFavoriteActionService? favoriteActionService,
  ThreadPostRateRepository? postRateRepository,
  ThreadPostCommentRepository? postCommentRepository,
  ThreadPollVoteRepository? pollVoteRepository,
  YamiboTagThreadPageRepository? tagThreadPageRepository,
  ThreadPostLocator? threadPostLocator,
  NativePageCacheInvalidationService? pageCacheInvalidationService,
  ImageCacheService? imageCacheService,
  ForumImagePrecacheService? forumImagePrecacheService,
  ForumWebViewDriverFactory? forumWebViewDriverFactory,
  ForumHtmlReaderPreferencesRepository? forumHtmlReaderPreferencesRepository,
  TextConverter Function(TextConversionMode mode)? textConverterFactory,
  bool diagnosticModeEnabled = false,
  HistoryVisitRecorder? historyVisitRecorder,
  HistoryDiagnosticRecorder? historyDiagnosticRecorder,
}) {
  return [
    historyVisitRecorderProvider.overrideWithValue(
      historyVisitRecorder ?? const _NoopHistoryVisitRecorder(),
    ),
    historyDiagnosticRecorderProvider.overrideWithValue(
      historyDiagnosticRecorder ?? const NoopHistoryDiagnosticRecorder(),
    ),
    threadRepositoryProvider.overrideWithValue(repository),
    if (forumHtmlReaderPreferencesRepository != null)
      forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
        forumHtmlReaderPreferencesRepository,
      ),
    if (textConverterFactory != null)
      textConverterProvider.overrideWith(
        (ref, mode) => textConverterFactory(mode),
      ),
    imageCacheServiceProvider.overrideWithValue(
      imageCacheService ?? _NoopImageCacheService(),
    ),
    if (forumImagePrecacheService != null)
      forumImagePrecacheServiceProvider.overrideWithValue(
        forumImagePrecacheService,
      ),
    nativePageCacheInvalidationServiceProvider.overrideWithValue(
      pageCacheInvalidationService ?? _FakeNativePageCacheInvalidationService(),
    ),
    novelRepositoryProvider.overrideWithValue(
      novelRepository ?? _FakeNovelRepository(),
    ),
    replyRepositoryProvider.overrideWithValue(
      replyRepository ?? _FakeReplyRepository(),
    ),
    threadFavoriteActionServiceProvider.overrideWithValue(
      favoriteActionService ?? _FakeThreadFavoriteActionService(),
    ),
    threadPostRateRepositoryProvider.overrideWithValue(
      postRateRepository ?? _FakeThreadPostRateRepository(),
    ),
    threadPostCommentRepositoryProvider.overrideWithValue(
      postCommentRepository ?? _FakeThreadPostCommentRepository(),
    ),
    threadPollVoteRepositoryProvider.overrideWithValue(
      pollVoteRepository ?? _FakeThreadPollVoteRepository(),
    ),
    threadPostLocatorProvider.overrideWithValue(
      threadPostLocator ?? _FakeThreadPostLocator(null),
    ),
    forumWebViewDriverFactoryProvider.overrideWith(
      (ref) => forumWebViewDriverFactory ?? _FakeForumWebViewDriver.new,
    ),
    cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
    webViewCookieSyncServiceProvider.overrideWithValue(
      _FakeWebViewCookieSyncService(),
    ),
    forumFavoriteRepositoryProvider.overrideWithValue(
      const _FakeForumFavoriteRepository(),
    ),
    forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
    yamiboTagThreadPageRepositoryProvider.overrideWithValue(
      tagThreadPageRepository ?? _FakeYamiboTagThreadPageRepository(),
    ),
    syncDiagnosticModeControllerProvider.overrideWith(
      () => _FakeSyncDiagnosticModeController(enabled: diagnosticModeEnabled),
    ),
    composerDraftRepositoryProvider.overrideWithValue(
      _MemoryComposerDraftRepository(),
    ),
    composerImagePickerProvider.overrideWithValue(_NoopComposerImagePicker()),
    composerImageUploadCoordinatorProvider.overrideWithValue(
      _NoopComposerImageUploadCoordinator(),
    ),
    composerUploadNotificationServiceProvider.overrideWithValue(
      _NoopComposerUploadNotificationService(),
    ),
  ];
}

class _RecordingHistoryVisitRecorder implements HistoryVisitRecorder {
  final List<HistoryVisitDraft> drafts = <HistoryVisitDraft>[];

  @override
  Future<void> record(HistoryVisitDraft draft) async {
    drafts.add(draft);
  }
}

class _ThrowingHistoryVisitRecorder implements HistoryVisitRecorder {
  const _ThrowingHistoryVisitRecorder();

  @override
  Future<void> record(HistoryVisitDraft draft) {
    throw StateError('history unavailable');
  }
}

class _NoopHistoryVisitRecorder implements HistoryVisitRecorder {
  const _NoopHistoryVisitRecorder();

  @override
  Future<void> record(HistoryVisitDraft draft) async {}
}

class _RecordingHistoryDiagnostics implements HistoryDiagnosticRecorder {
  final List<String> skipReasons = <String>[];

  @override
  void recordQuery({
    required HistoryDiagnosticOutcome outcome,
    required int elapsedMs,
    required bool searching,
    int? itemCount,
    bool? hasMore,
    String? errorType,
  }) {}

  @override
  void recordSkip({
    required HistoryVisitSurface surface,
    required String reason,
  }) {
    skipReasons.add(reason);
  }

  @override
  void recordWrite({
    required HistoryTargetType targetType,
    required HistoryVisitSurface surface,
    required HistoryDiagnosticOutcome outcome,
    required int elapsedMs,
    String? errorType,
  }) {}
}

ThreadDetailData _threadDetailData({
  required String tid,
  required List<ThreadPost> posts,
}) {
  return ThreadDetailData(
    tid: tid,
    fid: '2',
    subject: '测试主题',
    author: 'alice',
    replies: posts.length,
    views: 12,
    currentPage: 1,
    lastPage: 1,
    perPage: posts.length,
    posts: posts,
  );
}

class _FakeForumHtmlReaderPreferencesRepository
    implements ForumHtmlReaderPreferencesRepository {
  _FakeForumHtmlReaderPreferencesRepository(this.current);

  ForumHtmlReaderPreferences current;

  @override
  Future<ForumHtmlReaderPreferences> load() async => current;

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    current = preferences;
  }
}

class _FakeTextConverter implements TextConverter {
  const _FakeTextConverter(this.mode);

  @override
  final TextConversionMode mode;

  @override
  String get id => 'fake:${mode.name}';

  @override
  Future<String> convertHtml(String html) async {
    return switch (mode) {
      TextConversionMode.none => html,
      TextConversionMode.toSimplified => html.replaceAll('樣', '样'),
      TextConversionMode.toTraditional => html.replaceAll('样', '樣'),
    };
  }
}

class _ControlledExpandingTextConverter implements TextConverter {
  final _gate = Completer<void>();

  @override
  TextConversionMode get mode => TextConversionMode.toSimplified;

  @override
  String get id => 'controlled-expanding';

  @override
  Future<String> convertHtml(String html) async {
    await _gate.future;
    if (!html.contains('短首楼')) {
      return html.replaceAll('樣', '样');
    }
    return List<String>.filled(500, '异步扩展后的首楼正文').join(' ');
  }

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }
}

class _FakeSyncDiagnosticModeController extends SyncDiagnosticModeController {
  _FakeSyncDiagnosticModeController({required this.enabled});

  final bool enabled;

  @override
  Future<bool> build() async {
    return enabled;
  }
}

class _NoopImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(success: true, cacheKey: request.cacheKey);
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: request.sourcePath,
    );
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

class _FakeThreadDetailDiagnosticSettingsRepository
    implements ThreadDetailDiagnosticSettingsRepository {
  _FakeThreadDetailDiagnosticSettingsRepository({this.enabled = false});

  bool enabled;

  @override
  Future<bool> loadScrollDiagnosticEnabled() async => enabled;

  @override
  Future<void> setScrollDiagnosticEnabled(bool enabled) async {
    this.enabled = enabled;
  }
}

class _RecordingImageCacheService extends _NoopImageCacheService {
  final requests = <ImageCacheRequest>[];

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    requests.add(request);
    return CachedImageResult(success: true, cacheKey: request.cacheKey);
  }
}

class _RecordingForumImagePrecacheService implements ForumImagePrecacheService {
  final decodedSpecs = <ForumImageLoadSpec>[];

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async {
    return const ForumImagePrecacheResult(success: true);
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async {
    decodedSpecs.add(spec);
    return const ForumImagePrecacheResult(success: true, decoded: true);
  }
}

class _FakeNativePageCacheInvalidationService
    implements NativePageCacheInvalidationService {
  final invalidatedThreadIds = <String>[];
  final invalidatedForumDisplayIds = <String>[];
  var homeInvalidationCount = 0;

  @override
  Future<void> invalidateThread(String tid) async {
    invalidatedThreadIds.add(tid);
  }

  @override
  Future<void> invalidateForumDisplay(String fid) async {
    invalidatedForumDisplayIds.add(fid);
  }

  @override
  Future<void> invalidateForumHome() async {
    homeInvalidationCount++;
  }
}

ThreadPost _post({
  required String pid,
  required String author,
  required String authorId,
  required int number,
  required String message,
  bool isFirst = false,
}) {
  return ThreadPost(
    pid: pid,
    author: author,
    authorId: authorId,
    message: message,
    number: number,
    isFirst: isFirst,
    dateline: 'today',
  );
}

Finder _popupMenuText(String text) {
  return find.descendant(
    of: find.byType(PopupMenuItem<String>),
    matching: find.text(text),
  );
}

Finder _appBarTitleText(String text) {
  return find.descendant(
    of: find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(NavigationToolbar),
    ),
    matching: find.text(text),
  );
}

double _centerDxOf(WidgetTester tester, Finder finder) {
  return tester.getCenter(finder).dx;
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    return widget is RichText && widget.text.toPlainText().contains(text);
  });
}

Future<void> _longPressVisibleTop(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  final topLeft = tester.getTopLeft(finder);
  final size = tester.getSize(finder);
  final viewHeight =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final y = (topLeft.dy + 8).clamp(1.0, viewHeight - 1);
  final x = (topLeft.dx + size.width / 2).clamp(
    1.0,
    tester.view.physicalSize.width / tester.view.devicePixelRatio - 1,
  );
  await tester.longPressAt(Offset(x, y));
}

Future<void> _openPostAction(
  WidgetTester tester, {
  required Key bodyKey,
  required Key actionKey,
}) async {
  await _longPressVisibleTop(tester, find.byKey(bodyKey));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('thread-post-action-sheet')), findsOneWidget);
  await _tapPostActionSheetItem(tester, actionKey);
}

Future<void> _tapPostActionSheetItem(WidgetTester tester, Key key) async {
  final item = find.byKey(key);
  await tester.ensureVisible(item);
  await tester.pump();
  await tester.tap(item);
}

class _FakeForumTagRepository implements ForumTagRepository {
  @override
  Future<ForumTagLookup> loadLookup() async {
    return ForumTagLookup(const <ForumBoardTagSet>[
      ForumBoardTagSet(
        fid: '30',
        name: '中文百合漫画区',
        tags: <ForumTagDefinition>[
          ForumTagDefinition(fid: '30', typeid: '398', name: '韩国漫画'),
          ForumTagDefinition(fid: '30', typeid: '65', name: '公告'),
        ],
      ),
      ForumBoardTagSet(
        fid: '49',
        name: '文学区',
        tags: <ForumTagDefinition>[
          ForumTagDefinition(fid: '49', typeid: '293', name: '原创'),
          ForumTagDefinition(fid: '49', typeid: '121', name: '公告'),
        ],
      ),
    ]);
  }
}

class _FakeYamiboTagThreadPageRepository
    implements YamiboTagThreadPageRepository {
  final List<String> requestedUrls = <String>[];

  @override
  Future<ApiResult<YamiboTagThreadPageData>> load(String url) async {
    requestedUrls.add(url);
    return const ApiSuccess<YamiboTagThreadPageData>(
      YamiboTagThreadPageData(
        url:
            'https://bbs.yamibo.com/misc.php?mod=tag&id=20674&type=thread&page=1',
        tagId: '20674',
        tagName: '狱门抚子在此',
        pagination: YamiboTagPagePagination(currentPage: 1, totalPages: 1),
        threads: <YamiboTagThreadItem>[
          YamiboTagThreadItem(
            tid: '549277',
            threadUrl: 'https://bbs.yamibo.com/thread-549277-1-1.html',
            subject: '狱门抚子在此 00',
            forumName: '中文百合漫画区',
            replyCount: 24,
            viewCount: 6111,
          ),
        ],
      ),
    );
  }
}

class _FakeThreadFavoriteActionService implements ThreadFavoriteActionService {
  final ApiResult<ThreadFavoriteActionResult> result =
      const ApiSuccess<ThreadFavoriteActionResult>(
        ThreadFavoriteActionResult(
          message: '收藏成功',
          refreshedFavoriteModule: true,
          alreadyFavorited: false,
        ),
      );
  bool called = false;
  String? lastTid;

  @override
  Future<ApiResult<ThreadFavoriteActionResult>> favoriteThread({
    required String tid,
  }) async {
    called = true;
    lastTid = tid;
    return result;
  }
}

class _FakeThreadPollVoteRepository implements ThreadPollVoteRepository {
  bool called = false;
  ThreadPollVoteRequest? lastRequest;
  ApiResult<ThreadPollVoteResult> result =
      const ApiSuccess<ThreadPollVoteResult>(
        ThreadPollVoteResult(message: '投票成功'),
      );

  @override
  Future<ApiResult<ThreadPollVoteResult>> vote(
    ThreadPollVoteRequest request,
  ) async {
    called = true;
    lastRequest = request;
    return result;
  }
}

class _FakeThreadPostLocator implements ThreadPostLocator {
  _FakeThreadPostLocator(this.location);

  final ThreadPostLocation? location;
  String? lastTid;
  String? lastPid;
  Uri? lastSourceUri;

  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) async {
    lastTid = tid;
    lastPid = pid;
    lastSourceUri = sourceUri;
    final value = location;
    if (value == null) {
      return const ApiFailure<ThreadPostLocation>(
        ApiError(type: ApiErrorType.business, message: '测试未配置楼层定位'),
      );
    }
    return ApiSuccess<ThreadPostLocation>(value);
  }
}

class _FakeCookieStore extends CookieStore {
  @override
  Future<Map<String, String>> readCookieMap(Uri uri) async {
    return const <String, String>{};
  }

  @override
  Future<void> saveCookies(Uri uri, Map<String, String> cookies) async {}
}

class _FakeWebViewCookieJar implements WebViewCookieJar {
  @override
  Future<void> clear() async {}

  @override
  Future<Map<String, String>> readCookies(Uri uri) async {
    return const <String, String>{};
  }
}

class _FakeWebViewCookieSyncService extends WebViewCookieSyncService {
  _FakeWebViewCookieSyncService()
    : super(
        cookieJar: _FakeWebViewCookieJar(),
        cookieStore: _FakeCookieStore(),
      );

  @override
  Future<Map<String, String>> syncToStore(Uri uri) async {
    return const <String, String>{};
  }

  @override
  Future<void> clearWebViewCookies() async {}
}

class _FakeForumFavoriteRepository implements ForumFavoriteRepository {
  const _FakeForumFavoriteRepository();

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> favoriteForum({
    required String fid,
  }) async {
    return const ApiSuccess<ForumFavoriteMutationResult>(
      ForumFavoriteMutationResult(message: '收藏成功'),
    );
  }

  @override
  Future<ApiResult<List<FavoriteForum>>> loadFavoriteForums() async {
    return const ApiSuccess<List<FavoriteForum>>(<FavoriteForum>[]);
  }

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> unfavoriteForum({
    required String favid,
  }) async {
    return const ApiSuccess<ForumFavoriteMutationResult>(
      ForumFavoriteMutationResult(message: '取消收藏成功'),
    );
  }
}

class _FakeForumWebViewDriver implements ForumWebViewDriver {
  final List<Uri> loadedUris = <Uri>[];
  ForumWebViewBootstrapConfig? bootstrapConfig;
  ForumWebViewCallbacks? _callbacks;

  @override
  Widget buildWidget({Key? key}) {
    return SizedBox.expand(key: key);
  }

  @override
  Future<bool> canGoBack() async {
    return false;
  }

  @override
  Future<bool> clearCookies() async {
    return true;
  }

  @override
  Future<String?> getTitle() async {
    return '个人资料';
  }

  @override
  Future<void> goBack() async {}

  @override
  Future<void> initialize({
    required ForumWebViewCallbacks callbacks,
    required ForumWebViewBootstrapConfig bootstrapConfig,
  }) async {
    _callbacks = callbacks;
    this.bootstrapConfig = bootstrapConfig;
  }

  @override
  Future<void> load(Uri uri, {Map<String, String> headers = const {}}) async {
    loadedUris.add(uri);
    _callbacks?.onPageStarted(uri.toString());
    _callbacks?.onProgress(100);
    await _callbacks?.onPageFinished(uri.toString());
  }

  @override
  Future<ForumWebViewCapabilityProfile> probeCapabilities() async {
    return const ForumWebViewCapabilityProfile(
      engine: ForumWebViewEngine.advanced,
      documentStartMode: ForumWebViewDocumentStartMode.reliable,
      supportsContentBlockers: false,
      supportsTransparentBackground: true,
      supportsPlatformScrollTuning: true,
      supportsCookieHooks: true,
      supportsPageCommitVisible: true,
    );
  }

  @override
  Future<void> reload() async {}

  @override
  Future<void> runJavaScript(String script) async {}

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async {
    return null;
  }

  @override
  Future<void> seedCookies({
    required String domain,
    required Map<String, String> cookies,
    String path = '/',
  }) async {}
}

class _FakeThreadPostRateRepository implements ThreadPostRateRepository {
  String? loadedUrl;
  ThreadPostRateDraft? lastDraft;

  @override
  Future<ApiResult<ThreadPostRateForm>> loadForm(String rateUrl) async {
    loadedUrl = rateUrl;
    return _formResult();
  }

  @override
  Future<ApiResult<ThreadPostRateForm>> loadFormFromSeed(
    ThreadPostRateFormSeed seed,
  ) async {
    loadedUrl = seed.rateUrl;
    return _formResult(referer: seed.referer);
  }

  ApiResult<ThreadPostRateForm> _formResult({String? referer}) {
    return ApiSuccess<ThreadPostRateForm>(
      ThreadPostRateForm(
        actionUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&ratesubmit=yes',
        formHash: 'fh_rate',
        tid: '100',
        pid: 'p1',
        referer:
            referer ??
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
        scoreName: 'score1',
        scoreMin: 0,
        scoreMax: 5,
        todayRemaining: 10,
        reasonOptions: <String>['我很赞同', '精品文章'],
        notifyAuthorDefault: false,
      ),
    );
  }

  @override
  Future<ApiResult<ThreadPostRateResult>> submit(
    ThreadPostRateDraft draft,
  ) async {
    lastDraft = draft;
    return const ApiSuccess<ThreadPostRateResult>(
      ThreadPostRateResult(message: '评分成功'),
    );
  }
}

class _FakeThreadPostCommentRepository implements ThreadPostCommentRepository {
  String? loadedUrl;
  ThreadPostCommentFormSeed? loadedSeed;
  ThreadPostCommentDraft? lastDraft;

  @override
  Future<ApiResult<ThreadPostCommentForm>> loadForm(String commentUrl) async {
    loadedUrl = commentUrl;
    return _formResult(pid: 'p1');
  }

  @override
  Future<ApiResult<ThreadPostCommentForm>> loadFormFromSeed(
    ThreadPostCommentFormSeed seed,
  ) async {
    loadedSeed = seed;
    loadedUrl = seed.commentUrl;
    return _formResult(pid: seed.pid, tid: seed.tid);
  }

  ApiResult<ThreadPostCommentForm> _formResult({
    required String pid,
    String tid = '100',
  }) {
    return ApiSuccess<ThreadPostCommentForm>(
      ThreadPostCommentForm(
        actionUrl:
            'https://bbs.yamibo.com/forum.php?mod=post&action=reply&comment=yes&tid=$tid&pid=$pid&commentsubmit=yes',
        formHash: 'fh_comment',
        handleKey: 'comment',
        tid: tid,
        pid: pid,
        referer: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid',
        maxLength: 200,
      ),
    );
  }

  @override
  Future<ApiResult<ThreadPostCommentResult>> submit(
    ThreadPostCommentDraft draft,
  ) async {
    lastDraft = draft;
    return const ApiSuccess<ThreadPostCommentResult>(
      ThreadPostCommentResult(message: '点评成功'),
    );
  }
}

class _FakeReplyRepository implements ReplyRepository {
  bool called = false;
  ReplyDraft? lastDraft;

  @override
  Future<ApiResult<ReplySubmissionResult>> sendReply({
    required ReplyDraft draft,
  }) async {
    called = true;
    lastDraft = draft;
    return const ApiSuccess<ReplySubmissionResult>(
      ReplySubmissionResult(message: '回复发布成功'),
    );
  }

  @override
  Future<ApiResult<ReplyPreparation>> preparePostReply({
    required Uri replyFormUri,
  }) async {
    return const ApiFailure<ReplyPreparation>(
      ApiError(type: ApiErrorType.business, message: '测试不支持楼层回复准备'),
    );
  }
}

class _FakeThreadRepository implements ThreadRepository {
  _FakeThreadRepository(this._loader);

  final Function _loader;
  final List<Map<String, String>> queryHistory = <Map<String, String>>[];

  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
    Map<String, String> queryParameters = const <String, String>{},
  }) {
    queryHistory.add(Map<String, String>.from(queryParameters));
    final loader = _loader;
    if (loader
        is Future<ApiResult<ThreadDetailData>> Function(
          String,
          int,
          Map<String, String>,
        )) {
      return loader(tid, page, queryParameters);
    }
    return (loader
        as Future<ApiResult<ThreadDetailData>> Function(String, int))(
      tid,
      page,
    );
  }
}

class _MemoryComposerDraftRepository implements ComposerDraftRepository {
  final Map<ComposerDraftIdentity, ComposerDraftSnapshot> _drafts =
      <ComposerDraftIdentity, ComposerDraftSnapshot>{};

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {
    _drafts.remove(identity);
  }

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    return _drafts[identity];
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    return ComposerDraftPruneResult(removedCount: 0, keptCount: _drafts.length);
  }

  @override
  Future<void> saveDraft(ComposerDraftSnapshot snapshot) async {
    _drafts[snapshot.identity] = snapshot;
  }

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    return _drafts.values
        .where(
          (draft) => draft.identity.fid == fid && draft.identity.tid == tid,
        )
        .toList(growable: false);
  }
}

class _NoopComposerImagePicker implements ComposerImagePicker {
  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() async {
    return const <ComposerPickedImage>[];
  }
}

class _NoopComposerImageUploadCoordinator
    implements ComposerImageUploadCoordinator {
  @override
  void cancel() {}

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) {
    return const Stream<ComposerImageUploadEvent>.empty();
  }
}

class _NoopComposerUploadNotificationService
    implements ComposerUploadNotificationService {
  @override
  Future<void> clear() async {}

  @override
  Future<void> showFailure({
    required int failedCount,
    required int total,
  }) async {}

  @override
  Future<void> showProgress({required int current, required int total}) async {}
}

class _FakeNovelRepository implements NovelRepository {
  bool upsertCalled = false;
  bool refreshCalled = false;
  final Set<String> _ids = <String>{};

  @override
  Future<String> createCategory({required String name}) async => 'default';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return <NovelShelfCategory>[
      NovelShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    if (!_ids.contains(novelId)) {
      return null;
    }
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '49',
      sourceTypeId: null,
      sourceTagName: null,
      title: '测试小说',
      author: '作者A',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 5, 3),
      episodeCount: 1,
    );
  }

  @override
  Future<NovelChapterContent?> getChapterContent({
    required String episodeId,
  }) async => null;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return const <NovelEpisodeItem>[];
  }

  @override
  Future<List<NovelItem>> getShelfItems({
    String categoryId = 'default',
  }) async => const <NovelItem>[];

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<NovelReadingProgress?> getReadingProgress({
    required String novelId,
  }) async => null;

  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    refreshCalled = true;
    return const NovelEpisodeRefreshResult(
      insertedCount: 1,
      updatedCount: 0,
      totalCount: 1,
    );
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {
    _ids.remove(novelId);
  }

  @override
  Future<void> purgeWork({required String novelId}) async {
    _ids.remove(novelId);
  }

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    int? pageCount,
    String? anchorNodeId,
    int anchorTextOffset = 0,
    String? paginationKey,
    double progressPercent = 0,
  }) async {}

  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    upsertCalled = true;
    _ids.add('novel:${seed.fid}:${seed.tid}');
  }

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {}

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    return const <NovelReaderBookmark>[];
  }

  @override
  Future<void> removeReaderBookmark({required String bookmarkId}) async {}

  @override
  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  }) async {}
}
