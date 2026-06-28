import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' as riverpod_misc;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/cache/domain/native_page_cache_invalidation_service.dart';
import 'package:y300/features/favorites/data/favorite_first_sync_request_governor.dart';
import 'package:y300/features/composer_shared/data/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/composer_providers.dart';
import 'package:y300/features/composer_shared/data/composer_upload_notification_service.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/data/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/profile/data/models/user_profile_models.dart';
import 'package:y300/features/profile/data/user_profile_repository.dart';
import 'package:y300/features/tags/data/forum_tag_repository.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/tags/data/yamibo_tag_thread_page_repository.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';
import 'package:y300/features/tags/domain/models/yamibo_tag_thread_page.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_favorite_providers.dart';
import 'package:y300/features/thread/data/thread_detail_diagnostic_settings_repository.dart';
import 'package:y300/features/thread/data/thread_post_locator.dart';
import 'package:y300/features/thread/data/thread_post_comment_repository.dart';
import 'package:y300/features/thread/data/thread_post_rate_repository.dart';
import 'package:y300/features/thread/data/thread_poll_vote_repository.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';
import 'package:y300/features/thread/domain/models/thread_detail_diagnostic_event.dart';
import 'package:y300/features/thread/domain/services/thread_detail_diagnostic_recorder.dart';
import 'package:y300/features/thread/domain/services/thread_favorite_action_service.dart';
import 'package:y300/features/thread/presentation/thread_detail_diagnostic_controller.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';
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
      expect(find.byKey(const Key('thread-post-actions-p1')), findsOneWidget);
      expect(find.text('评分'), findsAtLeastNWidgets(1));
      expect(find.text('点评'), findsNWidgets(2));
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
      expect(find.text('电脑版'), findsOneWidget);
      expect(callCount, 2);

      await tester.tap(find.text('倒序浏览'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(repository.queryHistory.last['ordertype'], '1');
      expect(_richTextContaining('第一条回复'), findsOneWidget);
      expect(callCount, 3);
    });

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

    testWidgets('normal author avatar uses direct network image', (
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
      await tester.pumpAndSettle();

      final avatarImage = tester.widget<Image>(
        find
            .descendant(
              of: find.byKey(const Key('thread-author-avatar-p1')),
              matching: find.byType(Image),
            )
            .first,
      );
      expect(
        avatarImage.image,
        isA<NetworkImage>().having(
          (provider) => provider.url,
          'url',
          'https://bbs.yamibo.com/uc_server/data/avatar/000/00/00/01_avatar_small.jpg',
        ),
      );
    });

    testWidgets('does not schedule nearby post media preload in reader', (
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
        isFalse,
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
              event.entryKey == 'thread-post-header-p1',
        ),
        isTrue,
      );
      expect(
        events.any(
          (event) =>
              event.type == ThreadDetailDiagnosticEventType.continuousImage &&
              event.message.contains('imageItemBuilt'),
        ),
        isTrue,
      );
      expect(recorder.exportText(), contains('continuous=imageItemBuilt'));
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
        MaterialApp(
          home: Scaffold(
            body: ThreadDetailContent(
              state: state,
              imageHeaderBuilder: null,
              imageReferer:
                  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
              onLoadPreviousPage: () {},
              onLoadNextPage: () {},
              onLoadPageNumber: (_) {},
              onOpenPostReply: (_) {},
              onOpenPostRate: (_) {},
              onOpenPostComment: (_) {},
              onOpenAuthorProfile: (_) {},
              onCopyActionUrl: (_, _) {},
              onOpenPostLink: (_) {},
              onOpenPostCopyActions: (_, _) {},
              onTogglePollOption: (_, _) {},
              onSubmitPollVote: (_) {},
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
                  onOpenPostReply: (_) {},
                  onOpenPostRate: (_) {},
                  onOpenPostComment: (_) {},
                  onOpenAuthorProfile: (_) {},
                  onCopyActionUrl: (_, _) {},
                  onOpenPostLink: (_) {},
                  onOpenPostImages: (_, request) => opened = request,
                  onOpenPostCopyActions: (_, _) {},
                  onTogglePollOption: (_, _) {},
                  onSubmitPollVote: (_) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.byKey(const Key('thread-post-image-0')));
        await tester.pump();

        final bodySegment = tester.widget<ThreadPostBodySegmentView>(
          find.byType(ThreadPostBodySegmentView).first,
        );
        expect(
          bodySegment.resourceLayoutPolicy,
          ThreadPostResourceLayoutPolicy.adaptiveBlockImagesForReading,
        );
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

    testWidgets('current page button opens quick jump dialog and returns top', (
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

      expect(
        find.byKey(const Key('thread-detail-page-picker-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('thread-detail-page-plus-5-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('thread-detail-page-plus-10-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('thread-detail-page-plus-50-button')),
        findsOneWidget,
      );
      final plus50 = tester.widget<OutlinedButton>(
        find.byKey(const Key('thread-detail-page-plus-50-button')),
      );
      expect(plus50.onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('thread-detail-page-input')),
        '3',
      );
      await tester.tap(
        find.byKey(const Key('thread-detail-page-confirm-button')),
      );
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
      await tester.tap(
        find.byKey(const Key('thread-detail-page-plus-5-button')),
      );
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

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

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

    testWidgets('shows bottom tag links and opens native tag page', (
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
                message: '<p>正文</p>',
                number: 1,
                isFirst: true,
                dateline: 'today',
                tagLinks: const <ThreadPostTagLink>[
                  ThreadPostTagLink(
                    label: '狱门抚子在此',
                    url: 'https://bbs.yamibo.com/misc.php?mod=tag&id=20674',
                    tagId: '20674',
                  ),
                ],
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

      expect(find.byKey(const Key('thread-post-tag-links')), findsOneWidget);
      expect(find.text('狱门抚子在此'), findsOneWidget);

      await tester.tap(find.text('狱门抚子在此'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(tagRepository.requestedUrls.single, contains('id=20674'));
      expect(find.byKey(const Key('yamibo-tag-thread-page')), findsOneWidget);
      expect(find.text('狱门抚子在此'), findsWidgets);
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
    });

    testWidgets('locates findpost link before opening native thread page', (
      tester,
    ) async {
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
        _buildTestApp(repository, threadPostLocator: locator),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

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
      expect(list.cacheExtent, 900);
      expect(find.byKey(const Key('thread-post-card-bulk-0')), findsOneWidget);
      expect(find.byKey(const Key('thread-post-card-bulk-79')), findsNothing);
    });

    testWidgets('renders long text post as lazy body segments', (tester) async {
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
      expect(
        find.byKey(const Key('thread-post-body-long-1-0')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('thread-post-body-long-1-3')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('thread-post-body-long-1')),
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

    testWidgets('uses lazy body segment entries for image dense posts', (
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
      expect(
        find.byKey(const Key('thread-post-body-image-1-0')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('thread-post-body-image-1-6')), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('thread-post-body-image-1-6')),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(
        find.byKey(const Key('thread-post-body-image-1-6')),
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
      expect(
        find.byKey(const Key('thread-post-body-copy-1-0')),
        findsOneWidget,
      );
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
        find.byKey(const Key('thread-post-body-copy-1-0')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-post-copy-action-sheet')),
        findsOneWidget,
      );
      expect(find.text('选择复制'), findsOneWidget);
      expect(find.text('全部复制'), findsOneWidget);

      await tester.tap(find.byKey(const Key('thread-post-copy-all-action')));
      await tester.pumpAndSettle();

      expect(copiedTexts.single, contains('第一段链接文本'));
      expect(copiedTexts.single, contains('作者: 引用正文'));
      expect(copiedTexts.single, contains('尾段[笑]'));
      expect(copiedTexts.single, isNot(contains('page.jpg')));
      expect(find.text('1# 正文已复制'), findsOneWidget);

      await _longPressVisibleTop(
        tester,
        find.byKey(const Key('thread-post-body-copy-1-0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-post-select-copy-action')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-post-selectable-copy-page')),
        findsOneWidget,
      );
      expect(find.text('选择复制'), findsOneWidget);
      expect(
        find.byKey(const Key('thread-post-selectable-copy-body-copy-1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('thread-post-selectable-copy-body-copy-1')),
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
      final copyPageRichTexts = tester.widgetList<RichText>(
        find.descendant(
          of: find.byKey(const Key('thread-post-selectable-copy-body-copy-1')),
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

      expect(find.byKey(const Key('thread-post-image-0')), findsOneWidget);
      final image = tester.widget<Image>(
        find
            .descendant(
              of: find.byKey(const Key('thread-post-image-0')),
              matching: find.byType(Image),
            )
            .first,
      );
      final provider = image.image as NetworkImage;
      expect(
        provider.url,
        'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
      );
      expect(
        provider.headers?['Referer'],
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=1',
      );
      expect(provider.headers?['User-Agent'], contains('Chrome'));
      expect(provider.headers?['Accept'], contains('image/'));
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

      await tester.tap(find.text('评分'));
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

      await tester.tap(find.text('点评'));
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

      final postActions = find.byKey(const Key('thread-post-actions-p2'));
      expect(postActions, findsOneWidget);
      expect(
        find.descendant(of: postActions, matching: find.text('点评')),
        findsNothing,
      );
      expect(
        find.descendant(of: postActions, matching: find.text('回复')),
        findsOneWidget,
      );
      expect(commentRepository.loadedSeed, isNull);
      expect(commentRepository.loadedUrl, isNull);
    });

    testWidgets('hides local shelf entry for comic candidate post', (
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
                    '<img src="https://img.test/1.jpg"/><img src="https://img.test/2.jpg"/><a href="thread-100-1-1.html">1</a><a href="thread-101-1-1.html">2</a>',
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
      'includes second floor images when floor2 is same author and image-dominant',
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

        expect(
          find.byKey(const Key('comic-add-to-shelf-button')),
          findsNothing,
        );
      },
    );

    testWidgets('shows search-in-forum action when thread fid is 30', (
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
        findsOneWidget,
      );
    });

    testWidgets('opens user profile from post author name', (tester) async {
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

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('alice').first);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('user-profile-page-list')), findsOneWidget);
      expect(find.text('alice的资料'), findsWidgets);
      expect(find.text('5263'), findsOneWidget);
    });

    testWidgets('opens user profile from post author avatar', (tester) async {
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

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thread-author-avatar-p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('user-profile-page-list')), findsOneWidget);
      expect(find.text('alice的资料'), findsWidgets);
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
        find.byKey(const Key('reply-composer-message-input')),
        findsOneWidget,
      );
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
    ),
    child: const MaterialApp(
      home: ThreadDetailPage(tid: '100', subject: '测试主题'),
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
}) {
  return [
    threadRepositoryProvider.overrideWithValue(repository),
    imageCacheServiceProvider.overrideWithValue(
      imageCacheService ?? _NoopImageCacheService(),
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
    userProfileRepositoryProvider.overrideWithValue(
      const _FakeUserProfileRepository(),
    ),
    forumTagRepositoryProvider.overrideWithValue(_FakeForumTagRepository()),
    yamiboTagThreadPageRepositoryProvider.overrideWithValue(
      tagThreadPageRepository ?? _FakeYamiboTagThreadPageRepository(),
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

class _FakeUserProfileRepository implements UserProfileRepository {
  const _FakeUserProfileRepository();

  @override
  Future<ApiResult<UserProfileData>> getUserProfile({
    required String uid,
  }) async {
    return ApiSuccess<UserProfileData>(
      UserProfileData(
        uid: uid,
        username: 'alice',
        title: 'alice的资料',
        avatarUrl: 'https://bbs.yamibo.com/avatar.jpg',
        credits: const <UserProfileMetric>[
          UserProfileMetric(label: '总积分', value: '5263'),
        ],
        details: const <UserProfileDetailItem>[
          UserProfileDetailItem(label: 'UID', value: '509957'),
        ],
      ),
    );
  }

  @override
  Future<ApiResult<UserProfileData>> getMyProfile({required String uid}) async {
    return getUserProfile(uid: uid);
  }
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
  Future<NovelReaderPreferences> getReaderPreferences() async =>
      NovelReaderPreferences.defaults();

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

  @override
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
    String? anchorNodeId,
    double progressPercent = 0,
  }) async {}

  @override
  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    upsertCalled = true;
    _ids.add('novel:${seed.fid}:${seed.tid}');
  }

  @override
  Future<void> upsertReaderPreferences(
    NovelReaderPreferences preferences,
  ) async {}

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
