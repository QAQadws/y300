import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/tags/data/repositories/yamibo_tag_thread_page_repository.dart';
import 'package:y300/features/tags/domain/models/yamibo_tag_thread_page.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('renders native tag thread page and opens next page', (
    tester,
  ) async {
    final repository = _FakeTagThreadPageRepository();
    final theme = AppTheme.light();
    final palette = ForumDisplayThemePalette.resolve(theme);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yamiboTagThreadPageRepositoryProvider.overrideWithValue(repository),
        ],
        child: LocalizedTestApp(
          theme: theme,
          home: const YamiboTagThreadPage(
            url:
                'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const Key('yamibo-tag-thread-page')), findsOneWidget);
    expect(find.text('きさらぎ壱吾短篇集'), findsWidgets);
    expect(find.byKey(const Key('yamibo-tag-header-card')), findsOneWidget);
    expect(find.byKey(const Key('yamibo-tag-thread-572514')), findsOneWidget);
    expect(find.text('【个人汉化】[きさらぎ壱吾]晒猫'), findsOneWidget);
    expect(find.text('中文百合漫画区'), findsOneWidget);
    expect(
      _metricSemanticsLabel(tester, 'yamibo-tag-thread-replies-572514'),
      '回复 14',
    );
    expect(
      _metricSemanticsLabel(tester, 'yamibo-tag-thread-views-572514'),
      '查看 3092',
    );
    expect(find.text('14'), findsOneWidget);
    expect(find.text('3092'), findsOneWidget);
    expect(
      find.byKey(const Key('yamibo-tag-thread-attachment-572514')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('yamibo-tag-thread-last-post-572514')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('yamibo-tag-current-page-button')),
      findsOneWidget,
    );
    final currentPageButton = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(const Key('yamibo-tag-current-page-button')),
        matching: find.byType(TextButton),
      ),
    );
    final nextPageButton = tester.widget<TextButton>(
      find.byKey(const Key('yamibo-tag-next-page-button')),
    );
    final previousPageButton = tester.widget<TextButton>(
      find.byKey(const Key('yamibo-tag-previous-page-button')),
    );
    expect(
      currentPageButton.style?.foregroundColor?.resolve({}),
      palette.muted,
    );
    expect(nextPageButton.style?.foregroundColor?.resolve({}), palette.muted);
    expect(
      previousPageButton.style?.foregroundColor?.resolve({
        WidgetState.disabled,
      }),
      palette.disabledText,
    );
    expect(find.textContaining('id='), findsNothing);

    final list = tester.widget<ListView>(
      find.byKey(const Key('yamibo-tag-thread-list')),
    );
    expect(list.padding, const EdgeInsets.fromLTRB(10, 8, 10, 18));

    final headerFinder = find.byKey(const Key('yamibo-tag-header-card'));
    final threadSurfaceFinder = find.byKey(
      const Key('yamibo-tag-thread-surface-572514'),
    );
    final forumChipFinder = find.byKey(
      const Key('yamibo-tag-thread-forum-572514'),
    );
    final headerDecoration =
        tester.widget<DecoratedBox>(headerFinder).decoration as BoxDecoration;
    final threadDecoration =
        tester.widget<DecoratedBox>(threadSurfaceFinder).decoration
            as BoxDecoration;
    expect(
      headerDecoration.boxShadow,
      ForumNativeSurfaceShadows.card(palette.stateLayer),
    );
    expect(
      threadDecoration.boxShadow,
      ForumNativeSurfaceShadows.card(palette.stateLayer),
    );
    expect(headerDecoration.borderRadius, BorderRadius.circular(12));
    expect(threadDecoration.borderRadius, BorderRadius.circular(12));
    expect(
      tester.getTopLeft(threadSurfaceFinder).dy -
          tester.getBottomLeft(headerFinder).dy,
      8,
    );
    expect(
      tester.getTopRight(threadSurfaceFinder).dx -
          tester.getTopRight(forumChipFinder).dx,
      12,
    );
    expect(
      tester.getBottomRight(threadSurfaceFinder).dy -
          tester.getBottomRight(forumChipFinder).dy,
      11,
    );

    final title = tester.widget<Text>(
      find.byKey(const Key('yamibo-tag-thread-title-572514')),
    );
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(title.style?.fontWeight, FontWeight.w700);

    await tester.tap(find.byKey(const Key('yamibo-tag-next-page-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(repository.requestedUrls.last, contains('page=2'));
    expect(find.byKey(const Key('yamibo-tag-thread-572515')), findsOneWidget);

    await tester.tap(find.byKey(const Key('yamibo-tag-current-page-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('yamibo-tag-page-list')), findsOneWidget);
    expect(find.byKey(const Key('yamibo-tag-page-option-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('yamibo-tag-page-option-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(repository.requestedUrls.last, contains('page=1'));
    expect(find.byKey(const Key('yamibo-tag-thread-572514')), findsOneWidget);
  });

  testWidgets('localizes Traditional Chinese metrics and preserves raw data', (
    tester,
  ) async {
    final repository = _FakeTagThreadPageRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yamiboTagThreadPageRepositoryProvider.overrideWithValue(repository),
        ],
        child: const LocalizedTestApp(
          locale: Locale('zh', 'TW'),
          home: YamiboTagThreadPage(
            url:
                'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      _metricSemanticsLabel(tester, 'yamibo-tag-thread-replies-572514'),
      '回覆 14',
    );
    expect(
      _metricSemanticsLabel(tester, 'yamibo-tag-thread-views-572514'),
      '瀏覽 3092',
    );
    expect(find.text('【个人汉化】[きさらぎ壱吾]晒猫'), findsOneWidget);
  });

  testWidgets('omits missing metadata without empty separators or metrics', (
    tester,
  ) async {
    final repository = _FakeTagThreadPageRepository(
      includeOptionalMetadata: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yamiboTagThreadPageRepositoryProvider.overrideWithValue(repository),
        ],
        child: const LocalizedTestApp(
          home: YamiboTagThreadPage(
            url:
                'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byKey(const Key('yamibo-tag-thread-author-572514')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('yamibo-tag-thread-replies-572514')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('yamibo-tag-thread-views-572514')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('yamibo-tag-thread-forum-572514')),
      findsNothing,
    );
    expect(find.textContaining('·'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps compact hierarchy on narrow large-text dark surfaces', (
    tester,
  ) async {
    final repository = _FakeTagThreadPageRepository(
      tagName: '这是一个用于验证窄屏省略行为的非常长标签名称',
      useLongMetadata: true,
    );
    final theme = AppTheme.dark();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yamiboTagThreadPageRepositoryProvider.overrideWithValue(repository),
        ],
        child: LocalizedTestApp(
          theme: theme,
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(300, 700),
              textScaler: TextScaler.linear(1.7),
            ),
            child: YamiboTagThreadPage(
              url:
                  'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byKey(const Key('yamibo-tag-header-page-label')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('yamibo-tag-thread-forum-572514')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

String? _metricSemanticsLabel(WidgetTester tester, String keyValue) {
  final semantics = tester.widget<Semantics>(
    find
        .descendant(
          of: find.byKey(Key(keyValue)),
          matching: find.byType(Semantics),
        )
        .first,
  );
  return semantics.properties.label;
}

class _FakeTagThreadPageRepository implements YamiboTagThreadPageRepository {
  _FakeTagThreadPageRepository({
    this.includeOptionalMetadata = true,
    this.tagName = 'きさらぎ壱吾短篇集',
    this.useLongMetadata = false,
  });

  final bool includeOptionalMetadata;
  final String tagName;
  final bool useLongMetadata;
  final List<String> requestedUrls = <String>[];

  @override
  Future<ApiResult<YamiboTagThreadPageData>> load(String url) async {
    requestedUrls.add(url);
    final isPageTwo = Uri.tryParse(url)?.queryParameters['page'] == '2';
    return ApiSuccess<YamiboTagThreadPageData>(
      YamiboTagThreadPageData(
        url: url,
        tagId: '21920',
        tagName: tagName,
        pagination: YamiboTagPagePagination(
          currentPage: isPageTwo ? 2 : 1,
          totalPages: 2,
          nextPageUrl: isPageTwo
              ? null
              : 'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=2',
          previousPageUrl: isPageTwo
              ? 'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1'
              : null,
        ),
        threads: <YamiboTagThreadItem>[
          YamiboTagThreadItem(
            tid: isPageTwo ? '572515' : '572514',
            threadUrl:
                'https://bbs.yamibo.com/thread-${isPageTwo ? '572515' : '572514'}-1-1.html',
            subject: isPageTwo
                ? '【个人汉化】[きさらぎ壱吾]传闻中的二人'
                : useLongMetadata
                ? '【个人汉化】这是一个用于验证最多显示两行并安全省略的超长帖子标题'
                : '【个人汉化】[きさらぎ壱吾]晒猫',
            forumName: includeOptionalMetadata
                ? useLongMetadata
                      ? '这是一个非常长的论坛版块名称'
                      : '中文百合漫画区'
                : null,
            forumId: '30',
            authorName: includeOptionalMetadata
                ? useLongMetadata
                      ? '这是一个非常长的作者名称'
                      : '2440760273'
                : null,
            createdAt: includeOptionalMetadata ? '2026-6-15' : null,
            replyCount: includeOptionalMetadata
                ? isPageTwo
                      ? 13
                      : 14
                : null,
            viewCount: includeOptionalMetadata
                ? isPageTwo
                      ? 3523
                      : 3092
                : null,
            lastPosterName: includeOptionalMetadata ? 'hyrami' : null,
            lastPostAt: includeOptionalMetadata ? '2026-6-18 20:55' : null,
            hasImageAttachment: includeOptionalMetadata,
          ),
        ],
      ),
    );
  }
}
