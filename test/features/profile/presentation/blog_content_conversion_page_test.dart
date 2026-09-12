import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_preview.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_detail_fixture.dart';
import '../test_support/blog_operation_fixture.dart';
import '../test_support/blog_text_converter_fixture.dart';

void main() {
  testWidgets('translated editor preview never changes the submitted source', (
    tester,
  ) async {
    final host = _Host(BlogTextConverterFixture());
    const html = '<p class="keep">正文 &amp; literal</p>';
    host.operations.editorForm = (target) =>
        blogEditorPreparation(target, subject: '标题', bodyHtml: html);
    await host.pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BlogEditorPage(
                  target: UserBlogTarget(
                    actorUserId: '101',
                    ownerUserId: '101',
                    blogId: '11',
                    action: UserBlogAction.edit,
                  ),
                ),
              ),
            ),
            child: const Text('open fixture'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open fixture'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('blog-editor-preview-toggle')));
    await tester.pumpAndSettle();
    expect(
      _html(tester).single,
      '<h2>標題</h2><p class="keep">內文 &amp; literal</p>',
    );
    expect(host.operations.editorSubmissions, isEmpty);
    await tester.tap(find.byKey(const Key('blog-editor-preview-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('blog-editor-subject')))
          .controller!
          .text,
      '标题',
    );
    await tester.enterText(
      find.byKey(const Key('blog-editor-subject')),
      '修改标题',
    );
    final submit = find.byKey(const Key('blog-editor-submit'));
    await tester.scrollUntilVisible(
      submit,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('blog-editor-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(submit);
    await tester.pump();
    expect(host.operations.editorSubmissions.single.input.subject, '修改标题');
    expect(host.operations.editorSubmissions.single.input.bodyHtml, html);
    host.operations.saved();
    await tester.pumpAndSettle();
    expect(find.text('open fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'raw article is immediately readable, header and body share conversion, paging keeps it',
    (tester) async {
      final gate = Completer<void>();
      final host = _Host(BlogTextConverterFixture(gate: gate));
      const category = UserBlogCategoryLink(
        name: '文章分类',
        query: UserBlogDirectoryQuery.public(categoryId: '8'),
      );
      host.details.categoryLinks = const [category];
      await host.pump(
        tester,
        const ProfileBlogDetailPage(ownerUserId: '101', blogId: '11'),
      );
      expect(find.text('标题'), findsNWidgets(2));
      expect(find.text('文章分类'), findsOneWidget);
      expect(_html(tester), contains('<p>正文</p>'));
      expect(
        find.descendant(
          of: find.byType(ForumHtmlContentView),
          matching: find.text('评论', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(host.details.queries, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('標題'), findsNWidgets(2));
      expect(find.text('文章分類'), findsOneWidget);
      expect(find.byKey(ValueKey(category.query)), findsOneWidget);
      expect(_html(tester), contains('<p>內文</p>'));
      expect(_html(tester), contains('<p>評論</p>'));
      expect(
        find.descendant(
          of: find.byKey(const Key('blog-detail-author')),
          matching: find.text('作者'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('1 分鐘前'), findsOneWidget);
      expect(find.textContaining('作者變換'), findsNothing);
      expect(
        host.converter.inputs.where((value) => value.contains('标题')),
        hasLength(1),
      );
      final calls = host.converter.inputs.length;
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ProfileBlogDetailPage)),
      );
      await tester.ensureVisible(find.text(l10n.profileBlogMoreComments));
      await tester.tap(find.text(l10n.profileBlogMoreComments));
      await tester.pumpAndSettle();
      expect(host.details.queries, hasLength(2));
      expect(find.byKey(ValueKey(category.query)), findsOneWidget);
      expect(_html(tester), contains('<p>內文</p>'));
      expect(host.converter.inputs, hasLength(calls));
      await host.container
          .read(forumHtmlReaderPreferencesControllerProvider.notifier)
          .setFontScale(1.7);
      await tester.pumpAndSettle();
      expect(host.converter.inputs, hasLength(calls));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'translated summaries and categories still navigate with the raw identities',
    (tester) async {
      final host = _Host(BlogTextConverterFixture());
      await host.pump(tester, const ProfileBlogPage());
      expect(find.text('標題'), findsOneWidget);
      expect(find.text('摘錄'), findsOneWidget);
      expect(find.text('分類'), findsOneWidget);
      expect(find.text('作者'), findsOneWidget);
      await tester.tap(find.text('分類'));
      await tester.pumpAndSettle();
      expect(host.directory.queries.last.categoryId, '7');
      await tester.tap(find.text('標題'));
      await tester.pumpAndSettle();
      expect(host.details.queries.single.ownerUserId, '101');
      expect(host.details.queries.single.blogId, '11');
    },
  );

  testWidgets(
    'disabling conversion restores raw content without another read',
    (tester) async {
      final host = _Host(BlogTextConverterFixture());
      await host.pump(
        tester,
        const ProfileBlogDetailPage(ownerUserId: '101', blogId: '11'),
      );
      expect(find.text('標題'), findsNWidgets(2));
      host.mode = TextConversionMode.none;
      host.update();
      await tester.pumpAndSettle();
      expect(find.text('标题'), findsNWidgets(2));
      expect(_html(tester), contains('<p>正文</p>'));
      expect(host.details.queries, hasLength(1));
    },
  );

  for (final change in ['source', 'mode', 'account', 'dispose']) {
    testWidgets(
      'pending preview conversion cannot restore old content after $change',
      (tester) async {
        final gate = Completer<void>();
        final host = _Host(BlogTextConverterFixture(gate: gate));
        const original = BlogEditorDraft(
          subject: '旧标题',
          bodyHtml: '<p>旧正文</p>',
        );
        final draft = ValueNotifier(original);
        addTearDown(draft.dispose);
        await host.pump(
          tester,
          Scaffold(
            body: ValueListenableBuilder(
              valueListenable: draft,
              builder: (_, value, _) =>
                  BlogEditorPreview(draft: value, ownerId: '101'),
            ),
          ),
        );
        expect(_html(tester).single, '<h2>旧标题</h2><p>旧正文</p>');
        if (change == 'source') {
          draft.value = const BlogEditorDraft(
            subject: '新标题',
            bodyHtml: '<p>新正文</p>',
          );
        } else if (change == 'mode') {
          host.mode = TextConversionMode.none;
          host.update();
        } else if (change == 'account') {
          host.actor = '202';
          host.update();
          draft.value = const BlogEditorDraft(
            subject: '新标题',
            bodyHtml: '<p>新正文</p>',
          );
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        await tester.pump();
        gate.complete();
        await tester.pumpAndSettle();
        if (change == 'source' || change == 'account') {
          expect(_html(tester).single, '<h2>新標題</h2><p>新內文</p>');
        } else if (change == 'mode') {
          expect(_html(tester).single, '<h2>旧标题</h2><p>旧正文</p>');
        } else {
          expect(_html(tester), isEmpty);
        }
        expect(original.bodyHtml, '<p>旧正文</p>');
        expect(original.subject, '旧标题');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failed conversion preserves the article and comment controls', (
    tester,
  ) async {
    final host = _Host(BlogTextConverterFixture()..fail = true);
    await host.pump(
      tester,
      const ProfileBlogDetailPage(ownerUserId: '101', blogId: '11'),
    );
    expect(find.text('标题'), findsNWidgets(2));
    expect(_html(tester), contains('<p>正文</p>'));
    expect(
      find.byKey(const Key('profile-blog-comment-button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

List<String> _html(WidgetTester tester) => tester
    .widgetList<ForumHtmlContentView>(find.byType(ForumHtmlContentView))
    .map((widget) => widget.html)
    .toList();

class _Host {
  _Host(this.converter);
  final BlogTextConverterFixture converter;
  final details = BlogDetailFixture()
    ..title = '标题'
    ..authorName = '作者'
    ..publishedAtText = '1 分钟前'
    ..bodyHtml = '<p>正文</p>'
    ..commentHtml = '<p>评论</p>';
  final directory = _Directory();
  final preferences = _Preferences();
  final operations = BlogOperationFixture(autoPrepare: true);
  String actor = '101';
  TextConversionMode mode = TextConversionMode.toTraditional;
  late final container = ProviderContainer(overrides: overrides);
  List<Override> get overrides => [
    blogAccountIdProvider.overrideWithValue(actor),
    appServerContentConversionModeProvider.overrideWithValue(mode),
    textConverterProvider(converter.mode).overrideWithValue(converter),
    userBlogDetailRepositoryProvider.overrideWithValue(details),
    userBlogDirectoryRepositoryProvider.overrideWithValue(directory),
    forumImageRefererProvider.overrideWithValue('https://example.test/'),
    forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(preferences),
    userBlogNavigationProvider.overrideWithValue(null),
    userBlogOperationsProvider.overrideWithValue(operations),
  ];
  void update() => container.updateOverrides(overrides);
  Future<void> pump(WidgetTester tester, Widget home) async {
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }
}

class _Directory implements UserBlogDirectoryRepository {
  final queries = <UserBlogDirectoryQuery>[];
  @override
  final capabilities = UserBlogDirectorySourceCapabilities(
    values: DataCapabilitySet.supported(UserBlogDirectoryCapability.values),
    paginationPrecision: PaginationPrecision.exact,
  );
  @override
  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  load(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    queries.add(query);
    return DataReadSuccess(
      data: UserBlogDirectoryData(
        scope: query.scope,
        order: query.order,
        items: const [
          UserBlogSummary(
            blogId: '11',
            ownerUserId: '101',
            title: '标题',
            excerpt: '摘要',
            authorName: '作者',
          ),
        ],
        categories: const [UserBlogCategory(id: '7', name: '分类')],
        pagination: UserBlogPagination(currentPage: query.page),
      ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _Preferences implements ForumHtmlReaderPreferencesRepository {
  @override
  Future<ForumHtmlReaderPreferences> load() async =>
      ForumHtmlReaderPreferences.defaults();
  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {}
}
