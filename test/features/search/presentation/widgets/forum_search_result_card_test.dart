import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/search/presentation/widgets/forum_search_result_card.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('renders compact forum metadata and shared surface geometry', (
    tester,
  ) async {
    final theme = AppTheme.light();
    final palette = ForumDisplayThemePalette.resolve(theme);
    var tapped = false;

    await tester.pumpWidget(
      LocalizedTestApp(
        theme: theme,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ForumSearchResultCard(
              item: const ForumSearchTopicSummary(
                tid: '571160',
                title: '搜索结果标题',
                forumId: '30',
                authorName: '测试作者',
                publishedAtText: '2026-08-11',
              ),
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('搜索结果标题'), findsOneWidget);
    expect(find.text('测试作者 · 2026-08-11'), findsOneWidget);
    expect(find.text('TID：571160'), findsOneWidget);

    final card = find.byType(ForumSearchResultCard);
    final surface = tester.widget<Material>(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    expect(surface.color, palette.surfaceContainerLow);
    expect(surface.borderRadius, BorderRadius.circular(12));
    final shadowDecoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(of: card, matching: find.byType(DecoratedBox))
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(
      shadowDecoration.boxShadow,
      ForumNativeSurfaceShadows.card(palette.stateLayer),
    );

    final title = tester.widget<Text>(find.text('搜索结果标题'));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(title.style?.fontWeight, FontWeight.w700);

    await tester.tap(find.byType(InkWell));
    expect(tapped, isTrue);
  });

  testWidgets('omits missing metadata without empty separators', (
    tester,
  ) async {
    Future<void> pumpItem(ForumSearchTopicSummary item) {
      return tester.pumpWidget(
        LocalizedTestApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: ForumSearchResultCard(item: item, onTap: () {}),
            ),
          ),
        ),
      );
    }

    await pumpItem(
      const ForumSearchTopicSummary(
        tid: '1',
        title: '仅作者',
        forumId: '30',
        authorName: '作者',
      ),
    );
    expect(find.text('作者'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);

    await pumpItem(const ForumSearchTopicSummary(tid: '2', title: '无元信息'));
    expect(
      find.byKey(const Key('forum-search-result-metadata-2')),
      findsNothing,
    );
    expect(find.text('TID：2'), findsOneWidget);
  });

  testWidgets('keeps TID visible on a narrow large-text surface', (
    tester,
  ) async {
    final theme = AppTheme.dark();
    final palette = ForumDisplayThemePalette.resolve(theme);
    await tester.pumpWidget(
      LocalizedTestApp(
        theme: theme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(280, 600),
            textScaler: TextScaler.linear(1.8),
          ),
          child: Scaffold(
            body: SizedBox(
              width: 280,
              child: ForumSearchResultCard(
                item: const ForumSearchTopicSummary(
                  tid: '571160',
                  title: '这是一个很长的搜索结果标题用于验证窄屏布局',
                  forumId: '30',
                  authorName: '这是一个非常长的作者名称',
                  publishedAtText: '2026-08-11 10:33',
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('TID：571160'), findsOneWidget);
    final card = find.byType(ForumSearchResultCard);
    final surface = tester.widget<Material>(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    expect(surface.color, palette.surfaceContainerLow);
    expect(tester.takeException(), isNull);
  });
}
