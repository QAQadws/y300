import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/image_display_provider.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_link_navigation.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_detail_fixture.dart';
import '../test_support/blog_directory_fixture.dart';
import '../test_support/profile_repository_fixture.dart';

void main() {
  for (final query in [
    const UserBlogDirectoryQuery.public(
      categoryId: '7',
      order: UserBlogOrder.recommended,
      page: 3,
    ),
    const UserBlogDirectoryQuery.self(
      ownerUserId: '202',
      personalCategoryId: '8',
    ),
  ]) {
    testWidgets(
      'article category opens the exact ${query.scope} feed on demand',
      (tester) async {
        final host = _Host();
        host.details.categoryLinks = [
          UserBlogCategoryLink(name: 'Category fixture', query: query),
        ];
        await host.pump(
          tester,
          const ProfileBlogDetailPage(ownerUserId: '202', blogId: '12'),
        );
        expect(host.directory.queries, isEmpty);
        final category = find.byKey(ValueKey(query));
        expect(tester.getSize(category).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(category).width, greaterThanOrEqualTo(48));
        final button = tester.widget<TextButton>(category);
        button.onPressed!();
        button.onPressed!();
        await tester.pumpAndSettle();
        expect(host.directory.queries.single, query);
        expect(host.webLaunches, isEmpty);
        expect(host.external.uris, isEmpty);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
        expect(category, findsOneWidget);
        expect(host.details.queries, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('long category names wrap on narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = _Host();
    const query = UserBlogDirectoryQuery.public(categoryId: '7');
    host.details.categoryLinks = [
      UserBlogCategoryLink(name: 'Long category name ' * 6, query: query),
    ];
    await host.pump(
      tester,
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: ProfileBlogDetailPage(ownerUserId: '202', blogId: '12'),
      ),
    );
    final button = find.byKey(const ValueKey(query));
    final content = tester.getRect(
      find.byKey(const Key('blog-detail-categories')),
    );
    final bounds = tester.getRect(button);
    expect(bounds.left, greaterThanOrEqualTo(content.left));
    expect(bounds.right, lessThanOrEqualTo(content.right));
    expect(bounds.right, lessThan(tester.view.physicalSize.width));
    expect(tester.getSize(button).height, greaterThan(48));
    expect(tester.takeException(), isNull);
    expect(host.directory.queries, isEmpty);
  });

  for (final query in [
    const UserBlogDirectoryQuery.public(
      page: 3,
      categoryId: '7',
      order: UserBlogOrder.recommended,
    ),
    const UserBlogDirectoryQuery.self(
      ownerUserId: '202',
      page: 2,
      personalCategoryId: '8',
    ),
    const UserBlogDirectoryQuery.friends(page: 4),
  ]) {
    testWidgets(
      'feed link preserves ${query.scope} filters and page ${query.page}',
      (tester) async {
        final host = _Host();
        await host.pump(
          tester,
          _Link(host.navigation.directory(query).toString()),
        );
        expect(host.directory.queries, isEmpty);
        await _tapLink(tester);
        expect(find.byType(ProfileBlogPage), findsOneWidget);
        expect(host.directory.queries.single, query);
        expect(host.webLaunches, isEmpty);
        expect(host.external.uris, isEmpty);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('open-content-link')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final query in [
    const UserBlogDetailQuery(ownerUserId: '202', blogId: '12', page: 3),
    const UserBlogDetailQuery(
      ownerUserId: '202',
      blogId: '12',
      commentId: '42',
    ),
    const UserBlogDetailQuery(
      ownerUserId: '202',
      blogId: '12',
      lastCommentPage: true,
    ),
  ]) {
    testWidgets(
      'article link preserves page ${query.page}, comment ${query.commentId}, last=${query.lastCommentPage}',
      (tester) async {
        final host = _Host();
        await host.pump(
          tester,
          _Link(host.navigation.detail(query).toString()),
        );
        await _tapLink(tester);
        expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
        expect(host.details.queries.single, query);
        expect(host.webLaunches, isEmpty);
        if (query.lastCommentPage || query.commentId != null) {
          expect(
            tester
                .getTopLeft(
                  find.byKey(const Key('profile-blog-comments-heading')),
                )
                .dy,
            inInclusiveRange(56, 90),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'profile links use the explicit author and do not prefetch a journal',
    (tester) async {
      final host = _Host();
      await host.pump(
        tester,
        const _Link('home.php?mod=space&uid=202&do=profile'),
      );
      await _tapLink(tester);
      expect(find.byType(UserProfilePage), findsOneWidget);
      expect(host.profiles.queries.single.userId, '202');
      expect(host.directory.queries, isEmpty);
    },
  );

  testWidgets('two callbacks before a frame push only one destination', (
    tester,
  ) async {
    final host = _Host();
    await host.pump(
      tester,
      const _Link('home.php?mod=space&uid=202&do=profile'),
    );
    final button = tester.widget<TextButton>(
      find.byKey(const Key('open-content-link')),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-content-link')), findsOneWidget);
  });

  testWidgets(
    'unsupported forum context uses the account-bound browser unchanged',
    (tester) async {
      final host = _Host();
      const link = 'home.php?mod=space&do=blog&view=we&fuid=202&page=4';
      await host.pump(tester, const _Link(link));
      await _tapLink(tester);
      expect(
        host.webLaunches.single.initialUri,
        Uri.parse('https://bbs.yamibo.com/$link'),
      );
      expect(host.webLaunches.single.expectedAccountId, '101');
      expect(host.directory.queries, isEmpty);
      expect(host.details.queries, isEmpty);
    },
  );

  for (final link in [
    'https://elsewhere.test/article',
    'mailto:fixture@example.test',
    'https://bbs.yamibo.com:8443/article',
  ]) {
    testWidgets('external destination uses the existing launcher: $link', (
      tester,
    ) async {
      final host = _Host();
      await host.pump(tester, _Link(link));
      await _tapLink(tester);
      expect(host.external.uris.single, Uri.parse(link));
      expect(host.webLaunches, isEmpty);
      expect(host.details.queries, isEmpty);
    });
  }

  for (final link in [
    'javascript:alert(1)',
    'file:///tmp/a',
    'data:text/html,test',
    'https://user:secret@bbs.yamibo.com/home.php',
    '',
  ]) {
    testWidgets('invalid or executable URL is not launched: $link', (
      tester,
    ) async {
      final host = _Host();
      await host.pump(tester, _Link(link));
      await _tapLink(tester);
      expect(host.external.uris, isEmpty);
      expect(host.webLaunches, isEmpty);
      final l10n = AppLocalizations.of(tester.element(find.byType(_Link)));
      expect(find.text(l10n.forumWebViewOpenExternalFailed), findsOneWidget);
    });
  }

  for (final change in ['account', 'cover', 'dispose']) {
    testWidgets('late external failure does not affect a changed $change', (
      tester,
    ) async {
      final host = _Host();
      host.external.pending = Completer<bool>();
      await host.pump(tester, const _Link('https://elsewhere.test/article'));
      await tester.tap(find.byKey(const Key('open-content-link')));
      await tester.pump();
      if (change == 'account') {
        host.changeActor('202');
        await tester.pump();
        host.changeActor('101');
        await tester.pump();
      } else if (change == 'cover') {
        unawaited(
          host.navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('cover fixture')),
            ),
          ),
        );
        await tester.pumpAndSettle();
      } else {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      host.external.pending!.complete(false);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a real body fragment opens the selected comment and returns without rereading',
    (tester) async {
      final host = _Host();
      host.details.bodyHtml =
          '<p><a href="#comment_42">linked comment</a></p>'
          '${'<p>long article text</p>' * 60}';
      await host.pump(
        tester,
        const ProfileBlogDetailPage(ownerUserId: '101', blogId: '11'),
      );
      final scroll = _detailScroll(tester);
      final before = scroll.position.pixels;
      await _tapHtmlLink(tester, 'linked comment');
      await tester.pumpAndSettle();
      expect(host.details.queries, hasLength(2));
      expect(
        host.details.queries.last,
        const UserBlogDetailQuery(
          ownerUserId: '101',
          blogId: '11',
          commentId: '42',
        ),
      );
      expect(
        tester
            .getTopLeft(find.byKey(const Key('profile-blog-comments-heading')))
            .dy,
        inInclusiveRange(56, 90),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_detailScroll(tester).position.pixels, before);
      expect(host.details.queries, hasLength(2));
      expect(host.webLaunches, isEmpty);
    },
  );

  testWidgets('comment HTML links use the current article base', (
    tester,
  ) async {
    final host = _Host();
    host.details.commentHtml =
        '<p><a href="home.php?mod=space&amp;uid=202&amp;do=profile">linked author</a></p>';
    await host.pump(
      tester,
      const ProfileBlogDetailPage(
        ownerUserId: '101',
        blogId: '11',
        focusComments: true,
      ),
    );
    await _tapHtmlLink(tester, 'linked author');
    await tester.pumpAndSettle();
    expect(find.byType(UserProfilePage), findsOneWidget);
    expect(host.profiles.queries.single.userId, '202');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(host.details.queries, hasLength(1));
  });

  testWidgets(
    'comment entry stays stable when content above it changes height',
    (tester) async {
      final host = _Host();
      host.details.bodyHtml = '<p>long article text for layout</p>' * 70;
      await host.pump(
        tester,
        const ProfileBlogDetailPage(
          ownerUserId: '101',
          blogId: '11',
          focusComments: true,
        ),
      );
      final heading = find.byKey(const Key('profile-blog-comments-heading'));
      final before = tester.getTopLeft(heading);
      final extent = _detailScroll(tester).position.minScrollExtent;
      await host.container
          .read(forumHtmlReaderPreferencesControllerProvider.notifier)
          .setFontScale(2);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(heading), before);
      expect(_detailScroll(tester).position.minScrollExtent, lessThan(extent));
      expect(host.details.queries, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty targeted comments provide an explicit state and all-comments action',
    (tester) async {
      final host = _Host();
      host.details.emptyComments = true;
      await host.pump(
        tester,
        const ProfileBlogDetailPage(
          ownerUserId: '101',
          blogId: '11',
          commentId: '42',
          focusComments: true,
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ProfileBlogDetailPage)),
      );
      expect(find.text(l10n.profileBlogCommentsEmpty), findsOneWidget);
      await tester.tap(find.text(l10n.profileBlogAllComments));
      await tester.pumpAndSettle();
      expect(host.details.queries.last.commentId, isNull);
      expect(host.details.queries.last.page, 1);
    },
  );

  testWidgets(
    'a pending article image cannot block or displace the comment entry',
    (tester) async {
      final host = _Host();
      final cache = _PendingImageCache();
      host.imageCache = cache;
      host.details.bodyHtml =
          '<p>article above comments</p><img src="https://bbs.yamibo.com/data/attachment/home/fixture.png">';
      await host.pump(
        tester,
        const ProfileBlogDetailPage(
          ownerUserId: '101',
          blogId: '11',
          focusComments: true,
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      final heading = find.byKey(const Key('profile-blog-comments-heading'));
      expect(heading, findsOneWidget);
      expect(find.text('comment fixture', findRichText: true), findsOneWidget);
      expect(tester.getTopLeft(heading).dy, inInclusiveRange(56, 90));
      // Reveal the bottom of the article as well; offscreen images may remain
      // deferred while the targeted comment is immediately readable.
      _detailScroll(tester).position.jumpTo(-160);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CachedLibraryImage), findsOneWidget);
      expect(cache.keys, isNotEmpty);
      expect(cache.downloads, 0);
      final before = tester.getTopLeft(heading);
      final extent = _detailScroll(tester).position.minScrollExtent;

      // A real local PNG arrives after the comment is already readable. Its
      // wide ratio replaces the tall fallback above the scroll origin.
      final file = await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp('blog-layout-');
        final frame = await createTestImage(
          width: 120,
          height: 30,
          cache: false,
        );
        try {
          final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
          return await File(
            '${directory.path}/fixture.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          frame.dispose();
        }
      });
      addTearDown(() async {
        await file!.parent.delete(recursive: true);
      });
      final imageFinder = find.byType(CachedLibraryImage);
      final imageWidget = tester.widget<CachedLibraryImage>(imageFinder);
      final provider = resolveDownscaledFileImageProvider(
        localPath: file!.path,
        fit: imageWidget.fit,
        displaySize: tester.getSize(imageFinder),
        devicePixelRatio: MediaQuery.devicePixelRatioOf(
          tester.element(imageFinder),
        ),
      );
      addTearDown(provider.evict);
      // Complete the exact display provider in real asynchronous time before
      // releasing the fake cache lookup; no fixture disk IO runs in fake time.
      await tester.runAsync(
        () => precacheImage(provider, tester.element(heading)),
      );
      cache.result.complete(
        CachedImageResult(
          success: true,
          cacheKey: cache.keys.first,
          localPath: file.path,
          width: 120,
          height: 30,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(heading), before);
      expect(
        _detailScroll(tester).position.minScrollExtent,
        greaterThan(extent),
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image?.width == 120,
        ),
        findsOneWidget,
      );
      expect(host.details.queries, hasLength(1));
      expect(cache.downloads, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

ScrollableState _detailScroll(WidgetTester tester) => tester.state(
  find
      .descendant(
        of: find.byKey(const Key('profile-blog-detail')),
        matching: find.byType(Scrollable),
      )
      .first,
);
Future<void> _tapHtmlLink(WidgetTester tester, String text) async {
  // A paragraph can be wider than its link. Tap the actual glyph selection,
  // not the center of the full-width RichText render box.
  final paragraph = tester.renderObject<RenderParagraph>(
    find.text(text, findRichText: true),
  );
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      )
      .first;
  await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
}

Future<void> _tapLink(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-content-link')));
  await tester.pumpAndSettle();
}

class _Link extends ConsumerWidget {
  const _Link(this.url);
  final String url;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: TextButton(
      key: const Key('open-content-link'),
      onPressed: () => openBlogContentLink(context, ref, url),
      child: const Text('open fixture link'),
    ),
  );
}

class _Host {
  final navigation = YamiboForumClientBuilder(
    config: ForumClientConfig(siteOrigin: Uri.parse('https://bbs.yamibo.com')),
    network: _NoNetwork(),
  ).buildStandardClient().blogNavigation!;
  final directory = BlogDirectoryFixture();
  final details = BlogDetailFixture();
  final profiles = ProfileRepositoryFixture();
  final external = _External();
  final preferences = _Preferences();
  final navigator = GlobalKey<NavigatorState>();
  final webLaunches = <ForumWebViewLaunchConfig>[];
  ImageCacheService? imageCache;
  late final container = ProviderContainer(overrides: _overrides('101'));
  List<Override> _overrides(String? actor) => [
    blogAccountIdProvider.overrideWithValue(actor),
    userBlogNavigationProvider.overrideWithValue(navigation),
    userBlogDirectoryRepositoryProvider.overrideWithValue(directory),
    userBlogDetailRepositoryProvider.overrideWithValue(details),
    forumUserProfileRepositoryProvider.overrideWithValue(profiles),
    forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
    forumWebViewRouteFactoryProvider.overrideWithValue(_webRoute),
    forumWebViewExternalLauncherProvider.overrideWithValue(external),
    forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(preferences),
    if (imageCache != null)
      imageCacheServiceProvider.overrideWithValue(imageCache!),
  ];
  void changeActor(String? actor) =>
      container.updateOverrides(_overrides(actor));
  Route<Object?> _webRoute(ForumWebViewLaunchConfig config) {
    webLaunches.add(config);
    return MaterialPageRoute(
      builder: (_) =>
          Scaffold(appBar: AppBar(), body: const Text('browser fixture')),
    );
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    bool settle = true,
  }) async {
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(navigatorKey: navigator, home: home),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }
}

class _External implements ForumWebViewExternalLauncher {
  final uris = <Uri>[];
  Completer<bool>? pending;
  @override
  Future<bool> launch(Uri uri) {
    uris.add(uri);
    return pending?.future ?? Future.value(true);
  }
}

class _NoNetwork implements ForumClientNetwork {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Link resolution must not access the network');
}

class _PendingImageCache implements ImageCacheService {
  final result = Completer<CachedImageResult>();
  final keys = <String>[];
  int downloads = 0;
  @override
  Future<CachedImageResult?> getCached(String cacheKey) {
    keys.add(cacheKey);
    return result.future;
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) {
    downloads++;
    throw StateError('The local image must not require a download');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Preferences implements ForumHtmlReaderPreferencesRepository {
  ForumHtmlReaderPreferences value = ForumHtmlReaderPreferences.defaults();
  @override
  Future<ForumHtmlReaderPreferences> load() async => value;
  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    value = preferences;
  }
}
