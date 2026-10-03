import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/forum/presentation/forum_display_content_projection.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_widgets.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_thread_badges.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  for (final width in [320.0, 393.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'forum markers stay at the upper right at $width dp / $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final scrollController = ScrollController();
          addTearDown(scrollController.dispose);
          await tester.pumpWidget(
            ProviderScope(
              child: LocalizedTestApp(
                theme: AppTheme.light(),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: Scaffold(
                      body: ForumDisplayContent(
                        projection: ForumDisplayContentProjection.raw(
                          _state(),
                          mode: TextConversionMode.none,
                        ),
                        scrollController: scrollController,
                        filterAnchorKey: GlobalKey(),
                        headImageKey: GlobalKey(),
                        onLoadMore: () {},
                        onLoadPrevious: () {},
                        onSelectPage: (_) {},
                        onOpenFilter: (_) {},
                        onOpenThreadTag: (_) {},
                        onOpenThread: (_) {},
                        onCopyThreadLink: (_) {},
                        onOpenTopEntry: (_) {},
                        onOpenSubForum: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final group = find.byType(ForumThreadBadgeGroup);
          final l10n = AppLocalizations.of(tester.element(group));
          expect(find.text(l10n.forumThreadBadgeClosed), findsOneWidget);
          expect(find.text(l10n.forumThreadBadgeDigest), findsOneWidget);
          expect(find.text(l10n.forumThreadBadgeSticky), findsOneWidget);
          expect(find.text('关闭的主题'), findsNothing);
          final card = tester.getRect(
            find.byKey(const Key('forum-thread-100')),
          );
          final markers = tester.getRect(group);
          final author = tester.getRect(find.text('Source author'));
          final title = tester.getRect(find.text('Source title'));
          expect(markers.right, closeTo(card.right - 12, 0.01));
          expect(markers.top, closeTo(author.top, 0.01));
          expect(markers.left, greaterThanOrEqualTo(author.right));
          expect(title.top, greaterThan(markers.bottom));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

ForumDisplayPageState _state() => ForumDisplayPageState(
  fid: '30',
  title: 'Source forum',
  currentPage: 1,
  hasMore: false,
  isLoadingInitial: false,
  isLoadingMore: false,
  query: const ForumDisplayQuery(fid: '30'),
  threads: [
    ForumThreadSummary(
      tid: '100',
      subject: 'Source title',
      author: 'Source author',
      replies: 1,
      views: 20,
      dateline: '2026-10-03',
      badges: const [
        ForumThreadBadge(
          kind: ForumThreadBadgeKind.closed,
          sourceLabel: '关闭的主题',
        ),
        ForumThreadBadge(kind: ForumThreadBadgeKind.sticky, sourceLabel: '置顶'),
        ForumThreadBadge(kind: ForumThreadBadgeKind.digest, sourceLabel: '精华'),
      ],
    ),
  ],
);
