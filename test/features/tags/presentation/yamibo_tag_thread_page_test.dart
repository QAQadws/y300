import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/tags/domain/models/forum_tag_directory_models.dart';
import 'package:y300/features/tags/domain/repositories/forum_tag_directory_repository.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('renders topics and loads numeric next pages', (tester) async {
    final repository = _FakeForumTagDirectoryRepository();
    final theme = AppTheme.light();
    final palette = ForumDisplayThemePalette.resolve(theme);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumTagDirectoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: LocalizedTestApp(
          theme: theme,
          home: const YamiboTagThreadPage(tagId: '21920'),
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

    final headerDecoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const Key('yamibo-tag-header-card')),
                )
                .decoration
            as BoxDecoration;
    final threadDecoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const Key('yamibo-tag-thread-surface-572514')),
                )
                .decoration
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

    await tester.tap(find.byKey(const Key('yamibo-tag-next-page-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(repository.requestedPages, <int>[1, 2]);
    expect(find.byKey(const Key('yamibo-tag-thread-572515')), findsOneWidget);

    await tester.tap(find.byKey(const Key('yamibo-tag-current-page-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('yamibo-tag-page-list')), findsOneWidget);
    await tester.tap(find.byKey(const Key('yamibo-tag-page-option-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(repository.requestedPages, <int>[1, 2, 1]);
  });

  testWidgets('gates optional fields by read capabilities', (tester) async {
    final repository = _FakeForumTagDirectoryRepository(
      includeOptionalMetadata: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumTagDirectoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: const LocalizedTestApp(
          home: YamiboTagThreadPage(tagId: '21920'),
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
    expect(
      find.byKey(const Key('yamibo-tag-thread-last-post-572514')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('yamibo-tag-thread-attachment-572514')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps old content after refresh failure', (tester) async {
    final repository = _FakeForumTagDirectoryRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumTagDirectoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: const LocalizedTestApp(
          home: YamiboTagThreadPage(tagId: '21920'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    repository.failRefresh = true;

    await tester.drag(
      find.byKey(const Key('yamibo-tag-thread-list')),
      const Offset(0, 240),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('yamibo-tag-thread-572514')), findsOneWidget);
    expect(find.textContaining('加载失败'), findsOneWidget);
  });

  testWidgets('keeps compact layout on narrow large-text surfaces', (
    tester,
  ) async {
    final repository = _FakeForumTagDirectoryRepository(
      tagName: '这是一个用于验证窄屏省略行为的非常长标签名称',
      useLongMetadata: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumTagDirectoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: LocalizedTestApp(
          theme: AppTheme.dark(),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(300, 700),
              textScaler: TextScaler.linear(1.7),
            ),
            child: YamiboTagThreadPage(tagId: '21920'),
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

class _FakeForumTagDirectoryRepository implements ForumTagDirectoryRepository {
  _FakeForumTagDirectoryRepository({
    this.includeOptionalMetadata = true,
    this.tagName = 'きさらぎ壱吾短篇集',
    this.useLongMetadata = false,
  });

  final bool includeOptionalMetadata;
  final String tagName;
  final bool useLongMetadata;
  final List<int> requestedPages = <int>[];
  bool failRefresh = false;

  @override
  ForumTagDirectorySourceCapabilities get capabilities =>
      _capabilities(includeOptionalMetadata);

  @override
  Future<
    DataReadResult<ForumTagDirectoryData, ForumTagDirectoryReadCapabilities>
  >
  load(
    ForumTagDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    requestedPages.add(query.page);
    if (failRefresh && cachePolicy == CacheLoadPolicy.networkFirst) {
      return const DataReadFailure(
        kind: DataReadFailureKind.network,
        code: 'fake_network_failure',
        diagnosticMessage: '加载失败',
      );
    }
    final isPageTwo = query.page == 2;
    final topic = ForumTagTopicSummary(
      tid: isPageTwo ? '572515' : '572514',
      title: isPageTwo
          ? '【个人汉化】[きさらぎ壱吾]传闻中的二人'
          : useLongMetadata
          ? '【个人汉化】这是一个用于验证最多显示两行并安全省略的超长帖子标题'
          : '【个人汉化】[きさらぎ壱吾]晒猫',
      forumId: '30',
      forumName: includeOptionalMetadata
          ? useLongMetadata
                ? '这是一个非常长的论坛版块名称'
                : '中文百合漫画区'
          : null,
      authorId: includeOptionalMetadata ? '399468' : null,
      authorName: includeOptionalMetadata
          ? useLongMetadata
                ? '这是一个非常长的作者名称'
                : '2440760273'
          : null,
      createdAt: includeOptionalMetadata ? '2026-6-15' : null,
      replyCount: includeOptionalMetadata ? (isPageTwo ? 13 : 14) : null,
      viewCount: includeOptionalMetadata ? (isPageTwo ? 3523 : 3092) : null,
      lastPosterName: includeOptionalMetadata ? 'hyrami' : null,
      lastPostAt: includeOptionalMetadata ? '2026-6-18 20:55' : null,
      hasImageAttachment: includeOptionalMetadata ? true : null,
      hasAttachment: includeOptionalMetadata ? false : null,
    );
    final data = ForumTagDirectoryData(
      tag: ForumTagIdentity(id: '21920', name: tagName),
      topics: <ForumTagTopicSummary>[topic],
      pagination: ForumTagPagination(
        currentPage: query.page,
        totalPages: 2,
        hasPrevious: query.page > 1,
        hasNext: query.page < 2,
      ),
    );
    return DataReadSuccess(
      data: data,
      capabilities: _readCapabilities(includeOptionalMetadata),
      metadata: const DataReadMetadata.network(),
    );
  }

  ForumTagDirectoryReadCapabilities _readCapabilities(bool includeOptional) {
    final supported = <ForumTagDirectoryCapability>[
      ForumTagDirectoryCapability.stableTagIdentity,
      ForumTagDirectoryCapability.orderedTopics,
      ForumTagDirectoryCapability.stableTopicIdentity,
      ForumTagDirectoryCapability.topicTitle,
      ForumTagDirectoryCapability.tagName,
      ForumTagDirectoryCapability.directionalPagination,
      ForumTagDirectoryCapability.totalPageCount,
      if (includeOptional) ...[
        ForumTagDirectoryCapability.topicForum,
        ForumTagDirectoryCapability.topicAuthor,
        ForumTagDirectoryCapability.topicCreationTime,
        ForumTagDirectoryCapability.topicReplyCount,
        ForumTagDirectoryCapability.topicViewCount,
        ForumTagDirectoryCapability.topicLastPost,
        ForumTagDirectoryCapability.topicAttachmentFlags,
      ],
    ];
    return ForumTagDirectoryReadCapabilities(
      values: DataCapabilitySet<ForumTagDirectoryCapability>.from(
        supported: supported,
        unsupported: includeOptional
            ? const <ForumTagDirectoryCapability>[]
            : const <ForumTagDirectoryCapability>[
                ForumTagDirectoryCapability.topicForum,
                ForumTagDirectoryCapability.topicAuthor,
                ForumTagDirectoryCapability.topicCreationTime,
                ForumTagDirectoryCapability.topicReplyCount,
                ForumTagDirectoryCapability.topicViewCount,
                ForumTagDirectoryCapability.topicLastPost,
                ForumTagDirectoryCapability.topicAttachmentFlags,
              ],
      ),
      paginationPrecision: PaginationPrecision.exact,
    );
  }

  ForumTagDirectorySourceCapabilities _capabilities(bool includeOptional) {
    final read = _readCapabilities(includeOptional);
    return ForumTagDirectorySourceCapabilities(
      values: read.values,
      paginationPrecision: read.paginationPrecision,
    );
  }
}
