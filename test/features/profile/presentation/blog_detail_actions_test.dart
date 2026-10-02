import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_page.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_comment_fixture.dart';
import '../test_support/blog_detail_fixture.dart';
import '../test_support/blog_text_converter_fixture.dart';

void main() {
  for (final fromDrawer in [false, true]) {
    testWidgets(
      'guest ${fromDrawer ? 'drawer' : 'AppBar'} reply uses the login route',
      (tester) async {
        final host = _Host()..actor = null;
        await host.pump(tester);
        if (fromDrawer) {
          await _openSheet(tester);
          await _tapAction(tester, 'reply');
        } else {
          await tester.tap(find.byKey(const Key('blog-detail-reply')));
          await tester.pumpAndSettle();
        }
        expect(find.byType(LoginPage), findsOneWidget);
        expect(host.comments.preparations, isEmpty);
        expect(host.comments.submissions, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final entry in ['app-bar', 'title', 'body', 'padding']) {
    testWidgets('$entry replies to the article with the same add target', (
      tester,
    ) async {
      final host = _Host();
      await host.pump(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ProfileBlogDetailPage)),
      );
      expect(find.byKey(const Key('blog-detail-actions')), findsNothing);
      expect(find.byKey(const Key('blog-comment-actions-31')), findsNothing);
      expect(
        find.byKey(const Key('profile-blog-comment-button')),
        findsNothing,
      );
      expect(find.byType(SelectionArea), findsNothing);
      final reply = find.byKey(const Key('blog-detail-reply'));
      expect(tester.widget<IconButton>(reply).tooltip, l10n.profileBlogReply);
      expect(
        find.descendant(of: reply, matching: find.byIcon(Icons.reply)),
        findsOneWidget,
      );
      if (entry == 'app-bar') {
        await tester.tap(reply);
      } else {
        final card = find.byKey(const Key('blog-detail-card'));
        if (entry == 'title') {
          await tester.longPress(
            find.descendant(of: card, matching: find.text('Article 11')),
          );
        } else if (entry == 'body') {
          await tester.longPress(
            find.text('article fixture', findRichText: true),
          );
        } else {
          await tester.longPressAt(
            tester.getTopLeft(card) + const Offset(20, 3),
          );
        }
        await tester.pumpAndSettle();
        await _tapAction(tester, 'reply');
      }
      await tester.pumpAndSettle();
      expect(find.byType(BlogCommentPage), findsOneWidget);
      expect(
        host.comments.preparations.single.target,
        blogCommentFixtureTarget,
      );
      expect(host.comments.submissions, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final blocked in ['closed', 'unknown', 'unsupported']) {
    testWidgets(
      '$blocked commenting hides both article reply entrances but keeps copying',
      (tester) async {
        final host = _Host();
        if (blocked == 'unsupported') {
          host.details.readCapabilities = UserBlogDetailReadCapabilities(
            values: DataCapabilitySet.supported(
              UserBlogDetailCapability.values.where(
                (value) =>
                    value != UserBlogDetailCapability.commentingAvailability,
              ),
            ),
          );
        } else {
          host.details.commentsOpen = blocked == 'closed' ? false : null;
        }
        await host.pump(tester);
        expect(find.byKey(const Key('blog-detail-reply')), findsNothing);
        await _openSheet(tester);
        expect(
          find.byKey(const Key('blog-content-action-reply')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('blog-content-action-select-copy')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('blog-content-action-copy-all')),
          findsOneWidget,
        );
        expect(host.comments.preparations, isEmpty);
      },
    );
  }

  for (final comment in [false, true]) {
    testWidgets(
      '${comment ? 'comment' : 'article'} copies displayed body and its precise source link',
      (tester) async {
        final host = _Host()..convert = true;
        const markup =
            '<p>正文<br>第二行</p><blockquote>引用正文</blockquote>'
            '<p>结尾<img src="static/image/smiley/comcom/2.gif" alt="[笑]">'
            '<img src="data/attachment/home/photo.jpg" alt="图片"></p>';
        if (comment) {
          host.details.commentHtml = markup;
        } else {
          host.details.bodyHtml = markup;
        }
        final copied = _captureClipboard(tester);
        await host.pump(tester);
        await _openSheet(tester, comment: comment);
        await _tapAction(tester, 'copy-all');
        expect(copied, hasLength(1));
        expect(copied.single, contains('內文\n第二行'));
        expect(copied.single, contains('引用內文'));
        expect(copied.single, contains('结尾[笑]'));
        expect(copied.single, isNot(contains('Article 11')));
        expect(copied.single, isNot(contains('fixture author')));
        expect(copied.single, isNot(contains('photo.jpg')));
        expect(copied.single, isNot(contains('<p>')));
        expect(
          copied.single,
          isNot(contains(comment ? 'article fixture' : 'comment fixture')),
        );

        await _openSheet(tester, comment: comment);
        await _tapAction(tester, 'copy-link');
        expect(
          copied.last,
          host.navigation
              .detail(
                UserBlogDetailQuery(
                  ownerUserId: '202',
                  blogId: '11',
                  commentId: comment ? '31' : null,
                ),
              )
              .toString(),
        );
        expect(host.details.queries, hasLength(1));
        expect(host.comments.preparations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${comment ? 'comment' : 'article'} selection copy keeps formatted displayed HTML and clears on an account change',
      (tester) async {
        final host = _Host()..convert = true;
        host.details.bodyHtml =
            '<p><strong>正文</strong><a href="https://example.test/">链接</a></p>';
        host.details.commentHtml = '<blockquote>评论</blockquote>';
        await host.pump(tester);
        final sourceId = comment
            ? 'profile-blog-comment-31'
            : 'profile-blog-11';
        final original = tester.widget<ForumHtmlContentView>(
          find.byWidgetPredicate(
            (widget) =>
                widget is ForumHtmlContentView && widget.sourceId == sourceId,
          ),
        );
        await _openSheet(tester, comment: comment);
        await _tapAction(tester, 'select-copy');
        final page = find.byKey(const Key('blog-selection-copy-page'));
        expect(page, findsOneWidget);
        final html = tester.widget<ForumHtmlContentView>(
          find.descendant(
            of: page,
            matching: find.byType(ForumHtmlContentView),
          ),
        );
        expect(html.sourceId, sourceId);
        expect(html.html, original.html);
        expect(html.theme?.signature, original.theme?.signature);
        expect(html.onOpenLink, isNotNull);
        expect(html.onOpenImage, isNotNull);
        expect(
          find.ancestor(
            of: find.byKey(const Key('blog-selection-copy-body')),
            matching: find.byType(SelectionArea),
          ),
          findsOneWidget,
        );
        final texts = tester.widgetList<RichText>(
          find.descendant(of: page, matching: find.byType(RichText)),
        );
        expect(texts.any((text) => text.selectionRegistrar != null), isTrue);
        host.changeActor('303');
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: page,
            matching: find.byType(ForumHtmlContentView),
          ),
          findsNothing,
        );
        host.changeActor('101');
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: page,
            matching: find.byType(ForumHtmlContentView),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unavailable navigation hides copy-link only', (tester) async {
    final host = _Host()..withNavigation = false;
    await host.pump(tester);
    await _openSheet(tester);
    expect(
      find.byKey(const Key('blog-content-action-copy-link')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('blog-content-action-copy-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('blog-content-action-select-copy')),
      findsOneWidget,
    );
  });

  for (final action in ['reply', 'copy-all']) {
    testWidgets('an old $action drawer cannot run after A to B to A', (
      tester,
    ) async {
      final host = _Host();
      final copied = _captureClipboard(tester);
      await host.pump(tester);
      await _openSheet(tester);
      host.changeActor('303');
      await tester.pumpAndSettle();
      host.changeActor('101');
      await tester.pumpAndSettle();
      final staleAction = find.byKey(Key('blog-content-action-$action'));
      if (staleAction.evaluate().isNotEmpty) {
        await tester.tap(staleAction);
        await tester.pumpAndSettle();
      }
      expect(host.comments.preparations, isEmpty);
      expect(copied, isEmpty);
      expect(find.byType(BlogCommentPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _openSheet(WidgetTester tester, {bool comment = false}) async {
  final card = find.byKey(
    Key(comment ? 'profile-blog-comment-31' : 'blog-detail-card'),
  );
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.longPressAt(tester.getTopLeft(card) + const Offset(20, 3));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('blog-content-action-sheet')), findsOneWidget);
}

Future<void> _tapAction(WidgetTester tester, String action) async {
  final item = find.byKey(Key('blog-content-action-$action'));
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

List<String> _captureClipboard(WidgetTester tester) {
  final result = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        result.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return result;
}

class _Host {
  final details = BlogDetailFixture();
  final comments = BlogCommentFixture(autoPrepare: true);
  final preferences = _Preferences();
  final converter = BlogTextConverterFixture();
  final images = _Images();
  final navigation = YamiboForumClientBuilder(
    config: ForumClientConfig(siteOrigin: Uri.parse('https://bbs.yamibo.com')),
    network: _NoNetwork(),
  ).buildStandardClient().blogNavigation!;
  bool withNavigation = true;
  bool convert = false;
  String? actor = '101';
  late final container = ProviderContainer(overrides: overrides(actor));

  List<Override> overrides(String? actor) => [
    blogAccountIdProvider.overrideWithValue(actor),
    userBlogDetailRepositoryProvider.overrideWithValue(details),
    userBlogCommentServiceProvider.overrideWithValue(comments),
    imageCacheServiceProvider.overrideWithValue(images),
    userBlogNavigationProvider.overrideWithValue(
      withNavigation ? navigation : null,
    ),
    forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
    forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(preferences),
    appServerContentConversionModeProvider.overrideWithValue(
      convert ? converter.mode : TextConversionMode.none,
    ),
    textConverterProvider(converter.mode).overrideWithValue(converter),
  ];
  void changeActor(String? actor) =>
      container.updateOverrides(overrides(actor));

  Future<void> pump(WidgetTester tester) async {
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          home: ProfileBlogDetailPage(ownerUserId: '202', blogId: '11'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

class _Preferences implements ForumHtmlReaderPreferencesRepository {
  @override
  Future<ForumHtmlReaderPreferences> load() async =>
      ForumHtmlReaderPreferences.defaults();
  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {}
}

class _NoNetwork implements ForumClientNetwork {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Action links must not access the network');
}

class _Images implements ImageCacheService {
  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async =>
      const CachedImageResult(success: false);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
