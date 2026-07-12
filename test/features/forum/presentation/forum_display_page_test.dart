import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/forum/data/repositories/forum_display_repository.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';
import 'package:y300/features/forum/presentation/forum_display_page.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/features/forum/presentation/widgets/forum_home_widgets.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

void main() {
  group('ForumDisplayPage', () {
    test('light palette uses forum home native colors', () {
      final theme = AppTheme.light();
      final displayPalette = ForumDisplayThemePalette.resolve(theme);
      final homePalette = ForumHomeNativePalette.resolve(theme);

      expect(displayPalette.background, homePalette.background);
      expect(displayPalette.panel, homePalette.sectionBodyBackground);
      expect(displayPalette.card, homePalette.sectionBodyBackground);
      expect(displayPalette.accent, homePalette.sectionHeaderBackground);
      expect(
        displayPalette.surfaceContainer,
        homePalette.sectionBodyBackground,
      );
      expect(displayPalette.selectedContainer, isNot(Colors.transparent));
      expect(displayPalette.outlineSoft.a, lessThan(1));
      expect(displayPalette.stateLayer.a, lessThan(1));
      expect(
        displayPalette.threadBadgeBackground,
        theme.appBarTheme.backgroundColor,
      );
      expect(
        displayPalette.threadBadgeForeground,
        theme.appBarTheme.foregroundColor,
      );
      expect(displayPalette.threadBadgeOutline.a, lessThan(1));
    });

    test('dark palette remains derived from ColorScheme', () {
      final theme = AppTheme.dark();
      final palette = ForumDisplayThemePalette.resolve(theme);

      expect(palette.background, theme.scaffoldBackgroundColor);
      expect(palette.panel, theme.colorScheme.surfaceContainer);
      expect(palette.card, theme.colorScheme.surfaceContainerLowest);
      expect(palette.accent, theme.colorScheme.primary);
      expect(palette.surfaceContainer, theme.colorScheme.surfaceContainer);
      expect(
        palette.surfaceContainerLow,
        theme.colorScheme.surfaceContainerLowest,
      );
      expect(
        palette.surfaceContainerHigh,
        theme.colorScheme.surfaceContainerHighest,
      );
      expect(palette.selectedContainer, theme.colorScheme.secondaryContainer);
      expect(palette.threadBadgeBackground, theme.appBarTheme.backgroundColor);
      expect(palette.threadBadgeForeground, theme.appBarTheme.foregroundColor);
      expect(palette.threadBadgeOutline.a, lessThan(1));
    });

    testWidgets('stays buildable first then renders list', (tester) async {
      final completer = Completer<ApiResult<ForumDisplayData>>();
      final repository = _FakeForumDisplayRepository(
        (fid, page, query) => completer.future,
      );

      await tester.pumpWidget(
        _buildTestApp(repository, threadRepository: _FakeThreadRepository()),
      );

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byKey(const Key('forum-display-list')), findsNothing);

      completer.complete(
        ApiSuccess(
          _displayData(
            page: 1,
            total: 2,
            threads: [
              ForumThreadSummary(
                tid: '100',
                subject: '帖子A',
                author: 'alice',
                replies: 1,
                views: 5,
                dateline: 'today',
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('forum-display-list')), findsOneWidget);
      expect(
        find.byKey(const Key('forum-display-filter-header')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('forum-thread-list-group')), findsOneWidget);
      final selectedFilterIndicatorSize = tester.getSize(
        find
            .descendant(
              of: find.byKey(const Key('forum-display-filter-全部')),
              matching: find.byType(AnimatedContainer),
            )
            .last,
      );
      expect(selectedFilterIndicatorSize.width, 18);
      expect(selectedFilterIndicatorSize.height, 3);
      final selectedFilterIndicatorBottom = tester
          .getBottomLeft(
            find
                .descendant(
                  of: find.byKey(const Key('forum-display-filter-全部')),
                  matching: find.byType(AnimatedContainer),
                )
                .last,
          )
          .dy;
      final filterHeaderBottom = tester
          .getBottomLeft(find.byKey(const Key('forum-display-filter-header')))
          .dy;
      expect(
        (filterHeaderBottom - selectedFilterIndicatorBottom).abs(),
        lessThanOrEqualTo(1),
      );
      final filterHeaderCenterY = tester
          .getCenter(find.byKey(const Key('forum-display-filter-header')))
          .dy;
      final selectedFilterTextCenterY = tester.getCenter(find.text('全部')).dy;
      expect(
        (filterHeaderCenterY - selectedFilterTextCenterY).abs(),
        lessThanOrEqualTo(2),
      );
      expect(find.text('帖子A'), findsOneWidget);
      final palette = ForumDisplayThemePalette.resolve(
        Theme.of(tester.element(find.byType(ForumDisplayPage))),
      );
      expect(
        _threadCardShadowDecoration(tester, '100').boxShadow,
        ForumNativeSurfaceShadows.card(palette.stateLayer),
      );
      final metricChipContainer = tester.widget<Container>(
        find
            .ancestor(of: find.text('5'), matching: find.byType(Container))
            .first,
      );
      final metricChipDecoration =
          metricChipContainer.decoration as BoxDecoration;
      expect(metricChipDecoration.border, isNull);
      expect(find.text('公告区'), findsWidgets);
      expect(find.text('第1页'), findsOneWidget);

      await tester.tap(find.byKey(const Key('forum-thread-100')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar).last,
          matching: find.text('公告区'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AppBar).last,
          matching: find.text('帖子详情'),
        ),
        findsNothing,
      );
      Navigator.of(tester.element(find.byType(ThreadDetailPage))).pop();
      await tester.pumpAndSettle();

      const pageButtonKeys = [
        Key('forum-display-prev-page-button'),
        Key('forum-display-current-page-button'),
        Key('forum-display-load-more-button'),
      ];
      for (final key in pageButtonKeys) {
        final buttonWithKey = find.byKey(key);
        final descendantButton = find.descendant(
          of: buttonWithKey,
          matching: find.byType(TextButton),
        );
        final pageButton = tester.widget<TextButton>(
          descendantButton.evaluate().isEmpty
              ? buttonWithKey
              : descendantButton,
        );
        expect(
          pageButton.style?.backgroundColor?.resolve({}),
          palette.surfaceContainerHigh.withValues(alpha: 0.42),
        );
        final pageButtonShape =
            pageButton.style?.shape?.resolve({}) as RoundedRectangleBorder;
        expect(pageButtonShape.side, BorderSide.none);
        expect(pageButtonShape.borderRadius, BorderRadius.circular(10));
      }
    });

    testWidgets('pull refresh uses network-first forum display load', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 1,
            threads: [
              ForumThreadSummary(
                tid: '100',
                subject: '帖子A',
                author: 'alice',
                replies: 1,
                views: 5,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(repository.cachePolicies, <CacheLoadPolicy>[
        CacheLoadPolicy.cacheFirst,
      ]);

      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await indicator.onRefresh();
      await tester.pumpAndSettle();

      expect(repository.cachePolicies, <CacheLoadPolicy>[
        CacheLoadPolicy.cacheFirst,
        CacheLoadPolicy.networkFirst,
      ]);
    });

    testWidgets('default svg avatar uses local noavatar asset', (tester) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: 1,
            total: 1,
            threads: [
              ForumThreadSummary(
                tid: '100',
                subject: '帖子A',
                author: 'alice',
                replies: 1,
                views: 5,
                dateline: 'today',
                avatarUrl:
                    'https://bbs.yamibo.com/uc_server/data/avatar/noavatar.svg',
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
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is NetworkImage &&
              (widget.image as NetworkImage).url.contains('noavatar.svg'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('forum-thread-summary-avatar-100')),
          matching: find.byType(CachedLibraryImage),
        ),
        findsNothing,
      );
    });

    testWidgets('thread summary avatar uses avatar cache request', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: 1,
            total: 1,
            threads: [
              ForumThreadSummary(
                tid: '100',
                uid: '42',
                subject: '帖子A',
                author: 'alice',
                replies: 1,
                views: 5,
                dateline: 'today',
                avatarUrl:
                    'https://bbs.yamibo.com/uc_server/data/avatar/000/00/00/42_avatar_middle.jpg',
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
          of: find.byKey(const Key('forum-thread-summary-avatar-100')),
          matching: find.byType(CachedLibraryImage),
        ),
      );
      expect(avatarImage.request?.role, ImageCacheRole.avatar);
      expect(avatarImage.request?.ownerType, ImageCacheOwnerType.forumDisplay);
      expect(avatarImage.request?.ownerId, '42');
    });

    testWidgets('loads next page when tapping load more', (tester) async {
      var callCount = 0;
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        callCount++;
        if (page == 1) {
          return ApiSuccess(
            _displayData(
              page: 1,
              total: 2,
              threads: [
                ForumThreadSummary(
                  tid: '100',
                  subject: '帖子A',
                  author: 'alice',
                  replies: 1,
                  views: 5,
                  dateline: 'today',
                ),
              ],
            ),
          );
        }

        return ApiSuccess(
          _displayData(
            page: 2,
            total: 2,
            threads: [
              ForumThreadSummary(
                tid: '101',
                subject: '帖子B',
                author: 'bob',
                replies: 2,
                views: 6,
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
        find.byKey(const Key('forum-display-load-more-button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('forum-display-load-more-button')));
      await tester.pumpAndSettle();

      expect(find.text('帖子A'), findsNothing);
      expect(find.text('帖子B'), findsOneWidget);
      expect(callCount, 2);
    });

    testWidgets('long pressing thread copies thread link', (tester) async {
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

      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 1,
            threads: [
              ForumThreadSummary(
                tid: '572604',
                subject: '可复制链接的帖子',
                author: 'alice',
                replies: 0,
                views: 1,
                dateline: 'today',
                threadUrl:
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=572604&mobile=2',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.longPress(find.byKey(const Key('forum-thread-572604')));
      await tester.pump();

      expect(copiedTexts, [
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=572604&mobile=2',
      ]);
      expect(find.text('已复制帖子链接'), findsOneWidget);
    });

    testWidgets('long pressing thread falls back to tid link', (tester) async {
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

      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 1,
            threads: [
              ForumThreadSummary(
                tid: '100',
                subject: '只有 tid 的帖子',
                author: 'alice',
                replies: 0,
                views: 1,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.longPress(find.byKey(const Key('forum-thread-100')));
      await tester.pump();

      expect(copiedTexts, [
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&mobile=2',
      ]);
    });

    testWidgets('filter and thread tag taps reload using link query', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        final typeid = query?.parameters['typeid'];
        return ApiSuccess(
          _displayData(
            page: page,
            total: 10,
            threads: [
              ForumThreadSummary(
                tid: typeid == '65' ? 'top-filtered' : 'tag-filtered',
                subject: typeid == '65' ? '公告筛选结果' : '分类筛选结果',
                author: 'alice',
                replies: 0,
                views: 1,
                dateline: 'today',
                sourceTagName: '長篇連載',
                sourceTagUrl:
                    'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&filter=typeid&typeid=69&mobile=2',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tap(find.byKey(const Key('forum-display-type-filter-menu')));
      await tester.pumpAndSettle();
      final openTypeArrowFinder = find.descendant(
        of: find.byKey(const Key('forum-display-type-filter-menu')),
        matching: find.byType(RotationTransition),
      );
      final openTypeArrow =
          openTypeArrowFinder.evaluate().single.widget as RotationTransition;
      expect(openTypeArrow.turns.value, 0.5);
      final menuItemCenter = tester.getCenter(
        find.byKey(const Key('forum-display-type-filter-公告')),
      );
      final menuTextCenter = tester.getCenter(find.text('公告').last);
      expect((menuItemCenter.dx - menuTextCenter.dx).abs(), lessThan(1));

      await tester.tap(find.byKey(const Key('forum-display-type-filter-公告')));
      await tester.pumpAndSettle();

      expect(repository.lastQuery?.parameters['filter'], 'typeid');
      expect(repository.lastQuery?.parameters['typeid'], '65');
      expect(find.text('公告筛选结果'), findsOneWidget);

      await tester.tap(find.byKey(const Key('forum-thread-tag-top-filtered')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(repository.lastQuery?.parameters['typeid'], '69');
      expect(find.text('分类筛选结果'), findsOneWidget);
    });

    testWidgets(
      'filter, thread tag, and pagination return scroll to filter start',
      (tester) async {
        final repository = _FakeForumDisplayRepository((_, page, query) async {
          final typeid = query?.parameters['typeid'];
          final suffix = typeid == null ? 'page-$page' : 'type-$typeid';
          return ApiSuccess(
            _displayData(
              page: page,
              total: 24,
              lastPage: 8,
              headImageUrl:
                  'https://bbs.yamibo.com/data/attachment/album/202603/02/head.png',
              threads: _manyThreads(
                suffix: suffix,
                count: 12,
                includeTagUrl: true,
              ),
            ),
          );
        });

        await tester.pumpWidget(_buildTestApp(repository));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        final filterStartOffset = tester
            .getSize(find.byKey(const Key('forum-display-head-image')))
            .height;
        expect(_scrollOffset(tester), 0);
        expect(filterStartOffset, greaterThan(0));

        await _dragWellPastFilter(tester);
        expect(_scrollOffset(tester), greaterThan(filterStartOffset + 120));

        await tester.tap(find.byKey(const Key('forum-display-filter-最新')));
        await tester.pumpAndSettle();
        _expectReturnedToFilterStart(tester, filterStartOffset);
        expect(repository.lastQuery?.parameters['filter'], 'lastpost');

        await _dragWellPastFilter(tester);
        await tester.tap(
          find.byKey(const Key('forum-display-type-filter-menu')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('forum-display-type-filter-公告')));
        await tester.pumpAndSettle();
        _expectReturnedToFilterStart(tester, filterStartOffset);
        expect(repository.lastQuery?.parameters['typeid'], '65');

        await _dragWellPastFilter(tester);
        await tester.tap(find.byKey(const Key('forum-thread-tag-type-65-5')));
        await tester.pumpAndSettle();
        _expectReturnedToFilterStart(tester, filterStartOffset);
        expect(repository.lastQuery?.parameters['typeid'], '69');

        await _jumpNearBottomAndTap(
          tester,
          find.byKey(const Key('forum-display-load-more-button')),
        );
        await tester.pumpAndSettle();
        _expectReturnedToFilterStart(tester, filterStartOffset);
        expect(repository.lastQuery?.page, 2);

        await _jumpNearBottomAndTap(
          tester,
          find.byKey(const Key('forum-display-prev-page-button')),
        );
        await tester.pumpAndSettle();
        _expectReturnedToFilterStart(tester, filterStartOffset);
        expect(repository.lastQuery?.page, 1);

        await _jumpNearBottomAndTap(
          tester,
          find.byKey(const Key('forum-display-current-page-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('forum-display-page-option-3')));
        await tester.pumpAndSettle();

        _expectReturnedToFilterStart(tester, filterStartOffset);
        expect(repository.lastQuery?.page, 3);
      },
    );

    testWidgets('pinned entry opens thread detail', (tester) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 1,
            topEntries: const <ForumDisplayTopEntry>[
              ForumDisplayTopEntry(
                title: '置顶跳转',
                url:
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=535389&mobile=2',
                tid: '535389',
                badgeLabel: '置顶',
              ),
            ],
            threads: const <ForumThreadSummary>[],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final palette = ForumDisplayThemePalette.resolve(
        Theme.of(tester.element(find.byType(ForumDisplayPage))),
      );

      expect(find.text('置顶跳转'), findsNothing);
      expect(
        find.byKey(const Key('forum-display-top-entries-toggle')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('forum-display-top-entries-toggle')),
      );
      await tester.pumpAndSettle();

      expect(find.text('置顶跳转'), findsOneWidget);
      final topBadgeDecoration = _decorationAroundText(tester, '置顶');
      expect(topBadgeDecoration.border, isNull);
      expect(
        topBadgeDecoration.color,
        palette.surfaceContainerHigh.withValues(alpha: 0.42),
      );
      expect(topBadgeDecoration.boxShadow, isNotNull);
      expect(topBadgeDecoration.boxShadow, isNotEmpty);

      await tester.tap(
        find.byKey(const Key('forum-display-top-entries-toggle')),
      );
      await tester.pumpAndSettle();

      expect(find.text('置顶跳转'), findsNothing);

      await tester.tap(
        find.byKey(const Key('forum-display-top-entries-toggle')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('置顶跳转'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('置顶跳转'), findsWidgets);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isTrue);
    });

    testWidgets('current page button opens page menu and loads selected page', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 10,
            lastPage: 8,
            threads: [
              ForumThreadSummary(
                tid: 'page-$page',
                subject: '第$page页结果',
                author: 'alice',
                replies: 0,
                views: 1,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tap(
        find.byKey(const Key('forum-display-current-page-button')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('forum-display-page-list')), findsOneWidget);
      expect(find.byKey(const Key('forum-display-page-input')), findsNothing);
      expect(
        find.byKey(const Key('forum-display-page-option-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-display-page-option-8')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('forum-display-page-option-3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(repository.lastQuery?.page, 3);
      expect(find.text('第3页结果'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('forum-display-current-page-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forum-display-page-option-8')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(repository.lastQuery?.page, 8);
      expect(find.text('第8页结果'), findsOneWidget);
    });

    testWidgets('renders HTML-first forum chrome and pinned entries', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 52718,
            headImageUrl:
                'https://bbs.yamibo.com/data/attachment/album/202603/02/head.png',
            threads: [
              ForumThreadSummary(
                tid: '572604',
                subject: '[个人汉化]测试标题',
                author: 'nkdndixnx',
                replies: 0,
                views: 119,
                dateline: '2026-6-18 14:42',
                excerpt: '请勿随意转载，也请别在外网提及，谢谢',
                sourceTagName: '長篇連載',
                badgeLabel: '投票',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('forum-display-head-image')), findsOneWidget);
      final headImage = tester.widget<CachedLibraryImage>(
        find.descendant(
          of: find.byKey(const Key('forum-display-head-image')),
          matching: find.byType(CachedLibraryImage),
        ),
      );
      expect(headImage.request?.role, ImageCacheRole.forumHeadImage);
      expect(headImage.request?.ownerId, 'forum:2');
      expect(
        headImage.request?.effectiveRetentionClass,
        ImageRetentionClass.sticky,
      );
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('最新'), findsOneWidget);
      expect(
        find.byKey(const Key('forum-display-type-filter-menu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-display-compose-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-display-appbar-stats')),
        findsOneWidget,
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
      expect(find.text('今日 3'), findsOneWidget);
      expect(find.text('主题 52718'), findsOneWidget);
      expect(find.text('排名 1'), findsOneWidget);
      expect(find.text('发帖'), findsNothing);
      expect(
        find.byKey(const Key('forum-display-top-entries')),
        findsOneWidget,
      );
      expect(find.text('公告 / 置顶'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      expect(find.text('欢迎光临。'), findsNothing);

      await tester.drag(
        find.byKey(const Key('forum-display-list')),
        const Offset(0, -360),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('forum-display-top-entries-toggle')),
      );
      await tester.pumpAndSettle();

      expect(find.text('公告'), findsWidgets);
      expect(find.text('欢迎光临。'), findsOneWidget);
      expect(find.text('[个人汉化]测试标题'), findsOneWidget);
      expect(find.text('nkdndixnx'), findsOneWidget);
      expect(find.text('2026-6-18 14:42'), findsOneWidget);
      expect(find.textContaining('请勿随意转载'), findsOneWidget);
      expect(find.text('119'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('#長篇連載'), findsOneWidget);
      expect(find.text('投票'), findsOneWidget);

      final threadDecoration = _firstAnimatedContainerDecoration(
        tester,
        find.byKey(const Key('forum-thread-572604')),
      );
      expect(threadDecoration.border, isNull);

      final threadBadgeDecoration = _decorationAroundText(tester, '投票');
      expect(threadBadgeDecoration.boxShadow, isNotNull);
      expect(threadBadgeDecoration.boxShadow, isNotEmpty);
    });

    testWidgets('aligns thread tags to the same right edge', (tester) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 2,
            threads: [
              ForumThreadSummary(
                tid: 'tag-short',
                subject: '短 tag 帖子',
                author: 'alice',
                replies: 7,
                views: 86,
                dateline: 'today',
                excerpt: '短 tag 摘要',
                sourceTagName: '短',
              ),
              ForumThreadSummary(
                tid: 'tag-long',
                subject: '长 tag 帖子',
                author: 'bob',
                replies: 162,
                views: 1675,
                dateline: 'today',
                excerpt: '长 tag 摘要',
                sourceTagName: '八卦杂谈',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final shortTagRight = tester.getBottomRight(
        find.byKey(const Key('forum-thread-tag-tag-short')),
      );
      final longTagRight = tester.getBottomRight(
        find.byKey(const Key('forum-thread-tag-tag-long')),
      );

      expect((shortTagRight.dx - longTagRight.dx).abs(), lessThan(0.1));
    });

    testWidgets('clickable thread tag has a light shadow cue', (tester) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 1,
            threads: [
              ForumThreadSummary(
                tid: 'tag-clickable',
                subject: '带 tag 的帖子',
                author: 'alice',
                replies: 7,
                views: 86,
                dateline: 'today',
                excerpt: '摘要',
                sourceTagName: '長篇連載',
                sourceTagUrl:
                    'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&filter=typeid&typeid=69&mobile=2',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final tagFinder = find.byKey(const Key('forum-thread-tag-tag-clickable'));
      final decoratedBox = tester.widget<DecoratedBox>(
        find.descendant(of: tagFinder, matching: find.byType(DecoratedBox)),
      );
      final decoration = decoratedBox.decoration as BoxDecoration;

      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.single.blurRadius, 5);
      expect(decoration.border, isNull);
    });

    testWidgets('dark theme uses theme-driven forum display surfaces', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((fid, page, query) async {
        return ApiSuccess(
          _displayData(
            page: 1,
            total: 1,
            threads: const <ForumThreadSummary>[],
          ),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumDisplayRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const ForumDisplayPage(fid: '2', title: '公告区'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppTheme.dark().scaffoldBackgroundColor);
      expect(find.byKey(const Key('forum-display-list')), findsOneWidget);
      expect(
        find.byKey(const Key('forum-display-top-entries')),
        findsOneWidget,
      );
    });

    testWidgets('renders sub forum entry and opens nested forum display', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((fid, page, query) async {
        if (fid == '52') {
          return ApiSuccess(
            ForumDisplayData(
              fid: '52',
              forumName: '百合会最萌世界杯专版！',
              currentPage: 1,
              perPage: 20,
              totalThreads: 0,
              threads: const <ForumThreadSummary>[],
            ),
          );
        }

        return ApiSuccess(
          _displayData(
            page: page,
            total: 1,
            subForums: const <ForumDisplaySubForum>[
              ForumDisplaySubForum(
                fid: '52',
                title: '百合会最萌世界杯专版！',
                url:
                    'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=52&mobile=2',
                iconUrl:
                    'https://bbs.yamibo.com/data/attachment/common/9a/common_52_icon.gif',
              ),
            ],
            threads: const <ForumThreadSummary>[],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('forum-display-sub-forums')), findsOneWidget);
      expect(find.text('子版块'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('百合会最萌世界杯专版！'), findsNothing);

      await tester.tap(
        find.byKey(const Key('forum-display-sub-forums-toggle')),
      );
      await tester.pumpAndSettle();

      expect(find.text('百合会最萌世界杯专版！'), findsOneWidget);

      await tester.tap(find.byKey(const Key('forum-display-sub-forum-52')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isTrue);
      expect(find.text('百合会最萌世界杯专版！'), findsWidgets);
      expect(repository.lastQuery?.fid, '52');
    });

    testWidgets('opens search with the current forum fid', (tester) async {
      final repository = _FakeForumDisplayRepository((fid, page, query) async {
        return ApiSuccess(
          _displayData(
            fid: fid,
            page: 1,
            total: 1,
            threads: const <ForumThreadSummary>[],
          ),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumDisplayRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: ForumDisplayPage(fid: '30', title: '漫画区'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchButton = find.byKey(const Key('forum-display-search-button'));
      expect(searchButton, findsOneWidget);
      expect(
        tester
            .getCenter(find.byKey(const Key('forum-display-compose-button')))
            .dx,
        greaterThan(
          tester
              .getCenter(find.byKey(const Key('forum-display-search-button')))
              .dx,
        ),
      );

      await tester.tap(searchButton);
      await tester.pumpAndSettle();

      final searchPage = tester.widget<ForumSearchPage>(
        find.byType(ForumSearchPage),
      );
      expect(searchPage.context.scope, DiscuzSearchScope.curForum);
      expect(searchPage.context.srhfid, '30');
    });

    testWidgets('opens search with non-30 forum fid', (tester) async {
      final repository = _FakeForumDisplayRepository((fid, page, query) async {
        return ApiSuccess(
          _displayData(
            fid: fid,
            page: 1,
            total: 1,
            threads: const <ForumThreadSummary>[],
          ),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumDisplayRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: ForumDisplayPage(fid: '33', title: '海域区'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchButton = find.byKey(const Key('forum-display-search-button'));
      expect(searchButton, findsOneWidget);
      await tester.tap(searchButton);
      await tester.pumpAndSettle();

      final searchPage = tester.widget<ForumSearchPage>(
        find.byType(ForumSearchPage),
      );
      expect(searchPage.context.scope, DiscuzSearchScope.curForum);
      expect(searchPage.context.srhfid, '33');
    });

    testWidgets('hides search action when forum fid is empty', (tester) async {
      final repository = _FakeForumDisplayRepository((fid, page, query) async {
        return ApiSuccess(
          _displayData(
            fid: '',
            page: 1,
            total: 1,
            threads: const <ForumThreadSummary>[],
          ),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumDisplayRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: ForumDisplayPage(fid: '', title: ''),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('forum-display-search-button')),
        findsNothing,
      );
    });
  });
}

Widget _buildTestApp(
  ForumDisplayRepository repository, {
  ThreadRepository? threadRepository,
}) {
  final overrides = [
    forumDisplayRepositoryProvider.overrideWithValue(repository),
    imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
    if (threadRepository != null)
      threadRepositoryProvider.overrideWithValue(threadRepository),
  ];
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      home: ForumDisplayPage(fid: '2', title: '公告区'),
    ),
  );
}

ForumDisplayData _displayData({
  String fid = '2',
  required int page,
  required int total,
  required List<ForumThreadSummary> threads,
  List<ForumDisplayTopEntry>? topEntries,
  String? headImageUrl,
  List<ForumDisplaySubForum>? subForums,
  int? lastPage,
}) {
  return ForumDisplayData(
    fid: fid,
    forumName: '公告区',
    currentPage: page,
    perPage: 1,
    totalThreads: total,
    headImageUrl: headImageUrl,
    todayPosts: 3,
    rank: 1,
    lastPage: lastPage,
    previousPageUrl: page > 1
        ? 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&page=${page - 1}&mobile=2'
        : null,
    nextPageUrl: page < (lastPage ?? total)
        ? 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&page=${page + 1}&mobile=2'
        : null,
    hasMoreOverride: page < (lastPage ?? total),
    primaryFilters: const <ForumDisplayFilterItem>[
      ForumDisplayFilterItem(
        label: '全部',
        url: 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&mobile=2',
        isSelected: true,
      ),
      ForumDisplayFilterItem(
        label: '最新',
        url:
            'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&filter=lastpost&mobile=2',
      ),
    ],
    typeFilters: const <ForumDisplayFilterItem>[
      ForumDisplayFilterItem(
        label: '公告',
        url:
            'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&filter=typeid&typeid=65&mobile=2',
        typeid: '65',
      ),
    ],
    subForums: subForums ?? const <ForumDisplaySubForum>[],
    topEntries:
        topEntries ??
        const <ForumDisplayTopEntry>[
          ForumDisplayTopEntry(
            title: '欢迎光临。',
            url: 'https://bbs.yamibo.com/forum.php?mod=announcement&id=17',
            badgeLabel: '公告',
            isAnnouncement: true,
          ),
        ],
    threads: threads,
  );
}

List<ForumThreadSummary> _manyThreads({
  required String suffix,
  required int count,
  bool includeTagUrl = false,
}) {
  return [
    for (var index = 0; index < count; index++)
      ForumThreadSummary(
        tid: '$suffix-$index',
        subject: '帖子 $suffix-$index',
        author: 'alice',
        replies: index,
        views: 100 + index,
        dateline: 'today',
        excerpt: '用于制造滚动空间的摘要 $index',
        sourceTagName: '長篇連載',
        sourceTagUrl: includeTagUrl
            ? 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&filter=typeid&typeid=69&mobile=2'
            : null,
      ),
  ];
}

Future<void> _dragWellPastFilter(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const Key('forum-display-list')),
    const Offset(0, -620),
  );
  await tester.pumpAndSettle();
}

Future<void> _jumpNearBottomAndTap(WidgetTester tester, Finder finder) async {
  await _dragWellPastFilter(tester);
  final position = _scrollPosition(tester);
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

double _scrollOffset(WidgetTester tester) {
  return _scrollPosition(tester).pixels;
}

ScrollPosition _scrollPosition(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byKey(const Key('forum-display-list')),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );
  return tester.state<ScrollableState>(scrollable).position;
}

void _expectReturnedToFilterStart(WidgetTester tester, double expectedOffset) {
  expect((_scrollOffset(tester) - expectedOffset).abs(), lessThanOrEqualTo(1));
}

BoxDecoration _decorationAroundText(WidgetTester tester, String text) {
  final decoratedBox = tester.widget<DecoratedBox>(
    find
        .ancestor(of: find.text(text), matching: find.byType(DecoratedBox))
        .first,
  );
  return decoratedBox.decoration as BoxDecoration;
}

BoxDecoration _firstAnimatedContainerDecoration(
  WidgetTester tester,
  Finder root,
) {
  final containers = tester.widgetList<AnimatedContainer>(
    find.descendant(of: root, matching: find.byType(AnimatedContainer)),
  );
  for (final container in containers) {
    final decoration = container.decoration;
    if (decoration is BoxDecoration) {
      return decoration;
    }
  }
  throw StateError('No BoxDecoration AnimatedContainer found.');
}

BoxDecoration _threadCardShadowDecoration(WidgetTester tester, String tid) {
  final threadFinder = find.byKey(Key('forum-thread-$tid'));
  expect(threadFinder, findsOneWidget);
  final decoratedBoxes = find
      .ancestor(of: threadFinder, matching: find.byType(DecoratedBox))
      .evaluate();
  for (final element in decoratedBoxes) {
    final widget = element.widget as DecoratedBox;
    final decoration = widget.decoration;
    if (decoration is BoxDecoration &&
        decoration.boxShadow?.isNotEmpty == true) {
      return decoration;
    }
  }
  throw StateError('No thread card shadow decoration found.');
}

class _FakeForumDisplayRepository implements ForumDisplayRepository {
  _FakeForumDisplayRepository(this._loader);

  final Future<ApiResult<ForumDisplayData>> Function(
    String fid,
    int page,
    ForumDisplayQuery? query,
  )
  _loader;
  ForumDisplayQuery? lastQuery;
  final cachePolicies = <CacheLoadPolicy>[];

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page = 1,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    cachePolicies.add(cachePolicy);
    return _loader(fid, page, null);
  }

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplayByQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    lastQuery = query;
    cachePolicies.add(cachePolicy);
    return _loader(query.fid, query.page, query);
  }
}

class _NoopImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: 'memory://${request.cacheKey}',
      fromCache: true,
    );
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
      fromCache: true,
    );
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

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

class _FakeThreadRepository implements ThreadRepository {
  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
    Map<String, String> queryParameters = const <String, String>{},
  }) async {
    return ApiSuccess(
      ThreadDetailData(
        tid: tid,
        fid: '2',
        forumName: '公告区',
        subject: '帖子A',
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
  }
}
